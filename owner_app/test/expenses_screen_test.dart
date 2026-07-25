import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/expenses_screen.dart';

import 'support/test_harness.dart';

void main() {
  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  String monthParam(DateTime m) =>
      '${m.year}-${m.month.toString().padLeft(2, '0')}';

  final now = DateTime.now();
  final thisMonth = monthParam(DateTime(now.year, now.month));
  final prevMonth = monthParam(DateTime(now.year, now.month - 1));
  final dashPath = '/expenses/dashboard?month=$thisMonth';
  final prevDashPath = '/expenses/dashboard?month=$prevMonth';

  /// [marker] is echoed into both the insight text (rendered on the landing
  /// page) and the transaction title (rendered on ExpenseActivityScreen), so
  /// each test can assert on whichever surface it is exercising.
  Map<String, dynamic> dashboard({required String marker}) => {
        'month': thisMonth,
        'summary': {'total': 100, 'lastMonthTotal': 0},
        'categories': const [],
        'budgets': const [],
        'trend': const [],
        'pendingApprovals': {'count': 0, 'items': const []},
        'recentTransactions': [
          {
            'expenseId': 1,
            'title': marker,
            'category': 'FOOD',
            'amount': 100,
            'paymentMethod': 'CASH',
            'status': 'APPROVED',
            'expenseDate': '2026-07-05',
          },
        ],
        'pettyCash': const {},
        'insights': [marker],
      };

  group('ExpensesScreen reload', () {
    testWidgets('re-fetches the dashboard after an expense is created',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/owner/properties', {'items': const []})
        ..stubGet(dashPath, dashboard(marker: 'OLD-EXPENSE'))
        ..stubPost('/expenses', {'expenseId': 99, 'status': 'APPROVED'});

      await pumpDataScreen(tester, const ExpensesScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      expect(find.text('OLD-EXPENSE'), findsOneWidget);

      // The next dashboard fetch returns the new expense.
      fake.stubGet(dashPath, dashboard(marker: 'NEW-EXPENSE'));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'), 'NEW-EXPENSE');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (₹)'), '250');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(fake.postCalls, contains('/expenses'));
      expect(fake.getCalls.where((p) => p == dashPath).length, 2,
          reason: 'dashboard must be re-fetched after creating an expense');
      expect(find.text('NEW-EXPENSE'), findsOneWidget);
      expect(find.text('OLD-EXPENSE'), findsNothing);
    });

    testWidgets('app bar refresh icon re-fetches the dashboard', (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/owner/properties', {'items': const []})
        ..stubGet(dashPath, dashboard(marker: 'OLD-EXPENSE'));

      await pumpDataScreen(tester, const ExpensesScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      expect(find.text('OLD-EXPENSE'), findsOneWidget);

      fake.stubGet(dashPath, dashboard(marker: 'REFRESHED'));
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();

      expect(fake.getCalls.where((p) => p == dashPath).length, 2);
      expect(find.text('REFRESHED'), findsOneWidget);
    });

    testWidgets('month switcher fetches the selected month', (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/owner/properties', {'items': const []})
        ..stubGet(dashPath, dashboard(marker: 'CURRENT-MONTH-TXN'))
        ..stubGet(prevDashPath, dashboard(marker: 'PREV-MONTH-TXN'));

      await pumpDataScreen(tester, const ExpensesScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      expect(find.text('CURRENT-MONTH-TXN'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(fake.getCalls, contains(prevDashPath));
      expect(find.text('PREV-MONTH-TXN'), findsOneWidget);
      expect(find.text('CURRENT-MONTH-TXN'), findsNothing);

      // Forward again to the current month.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('CURRENT-MONTH-TXN'), findsOneWidget);

      // Cannot go past the current month: no future-month fetch is issued.
      final callsBefore = fake.getCalls.length;
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(fake.getCalls.length, callsBefore);
    });
  });

  group('ExpenseActivityScreen', () {
    Widget activity({int page = 1}) => ExpenseActivityScreen(
          propertyId: null,
          scopeLabel: 'All Properties',
          month: DateTime(now.year, now.month),
          initialPage: page,
        );

    testWidgets('category filter chips narrow the transactions page',
        (tester) async {
      final dash = dashboard(marker: 'FOOD-TXN');
      dash['recentTransactions'] = [
        ...dash['recentTransactions'] as List,
        {
          'expenseId': 2,
          'title': 'RENT-TXN',
          'category': 'RENT',
          'amount': 500,
          'paymentMethod': 'UPI',
          'status': 'APPROVED',
          'expenseDate': '2026-07-03',
        },
      ];
      final fake = FakeApiClient()..stubGet(dashPath, dash);

      await pumpDataScreen(tester, activity(), state: ownerState(fake));
      await tester.pumpAndSettle();
      expect(find.text('FOOD-TXN'), findsOneWidget);
      expect(find.text('RENT-TXN'), findsOneWidget);

      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.text('RENT-TXN'), findsOneWidget);
      expect(find.text('FOOD-TXN'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('FOOD-TXN'), findsOneWidget);
      expect(find.text('RENT-TXN'), findsOneWidget);
    });

    testWidgets('the pinned month switcher refetches for both pages',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGet(dashPath, dashboard(marker: 'CURRENT-TXN'))
        ..stubGet(prevDashPath, dashboard(marker: 'PREV-TXN'));

      await pumpDataScreen(tester, activity(), state: ownerState(fake));
      await tester.pumpAndSettle();
      expect(find.text('CURRENT-TXN'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();

      expect(fake.getCalls, contains(prevDashPath));
      expect(find.text('PREV-TXN'), findsOneWidget);
      // The month header stays put while the pages change under it.
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    });
  });
}
