import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/expenses_screen.dart';

import 'support/test_harness.dart';

/// The expenses dashboard is property-scoped in these tests (no `/owner/properties`
/// fetch) and pinned to one expense so the Recent Transactions row is unambiguous.
Map<String, dynamic> _dashboard({String status = 'APPROVED'}) => {
      'month': '2026-07',
      'summary': {'total': 4500, 'lastMonthTotal': 4000, 'changePct': 12},
      'categories': [
        {'category': 'FOOD', 'total': 4500},
      ],
      'budgets': const [],
      'trend': const [],
      'pendingApprovals': {
        'count': 1,
        'items': [
          {
            'expenseId': 88,
            'title': 'Plumber visit',
            'category': 'MAINTENANCE',
            'vendorName': 'Ravi',
            'amount': 800,
            'expenseDate': '2026-07-22',
          },
        ],
      },
      'recentTransactions': [
        {
          'expenseId': 77,
          'title': 'Vegetables',
          'category': 'FOOD',
          'amount': 4500,
          'paymentMethod': 'CASH',
          'status': status,
          'expenseDate': '2026-07-20',
        },
      ],
      'pettyCash': {'opening': 0, 'in': 0, 'out': 0, 'balance': 0},
      'insights': const <String>[],
    };

const _monthPath = '/expenses/dashboard?propertyId=9&month=';

String _dashPath() {
  final now = DateTime.now();
  return '$_monthPath${now.year}-${now.month.toString().padLeft(2, '0')}';
}

/// Transactions live on [ExpenseActivityScreen] (page 1), not the landing page.
Future<void> _pumpActivity(WidgetTester tester, FakeApiClient api,
    {int page = 1}) async {
  final state = AppState(apiClient: api)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';
  await pumpDataScreen(
    tester,
    ExpenseActivityScreen(
      propertyId: 9,
      scopeLabel: 'Sunrise PG',
      month: DateTime.now(),
      initialPage: page,
    ),
    state: state,
  );
  await tester.pumpAndSettle();
}

Future<void> _openRowMenu(WidgetTester tester) async {
  final menu = find.byTooltip('Expense actions');
  await tester.scrollUntilVisible(menu, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

void main() {
  group('Expense row actions', () {
    testWidgets('Edit loads the full row and PUTs the corrected amount',
        (tester) async {
      final api = FakeApiClient()
        ..stubGet(_dashPath(), _dashboard())
        ..stubGet('/expenses/77', {
          'expenseId': 77,
          'propertyId': 9,
          'title': 'Vegetables',
          'category': 'FOOD',
          'description': 'weekly market run',
          'amount': 4500,
          'paymentMethod': 'CASH',
          'vendorName': 'Green Mart',
          'status': 'APPROVED',
          'expenseDate': '2026-07-20',
          'editable': true,
          'lockedReason': null,
        })
        ..stubPut('/expenses/77', {'expenseId': 77, 'status': 'APPROVED'});

      await _pumpActivity(tester, api);
      await _openRowMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Sheet opened in edit mode, prefilled from the detail fetch.
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(find.text('Update Expense'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Green Mart'), findsOneWidget);
      // Approval is a status change, never part of an edit.
      expect(find.text('Requires approval'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextFormField, '4500.00'), '450');
      await tester.tap(find.text('Update Expense'));
      await tester.pumpAndSettle();

      expect(api.putCalls, contains('/expenses/77'));
      expect(api.putBodies.single['amount'], 450);
      expect(api.putBodies.single['propertyId'], 9);
      // Status stays with PATCH /status.
      expect(api.putBodies.single.containsKey('requiresApproval'), isFalse);
    });

    testWidgets('a salary-linked expense is refused before the sheet opens',
        (tester) async {
      final api = FakeApiClient()
        ..stubGet(_dashPath(), _dashboard())
        ..stubGet('/expenses/77', {
          'expenseId': 77,
          'title': 'July salary',
          'category': 'SALARY',
          'amount': 4500,
          'paymentMethod': 'CASH',
          'status': 'PAID',
          'expenseDate': '2026-07-20',
          'editable': false,
          'lockedReason':
              'This is a staff salary payment. Manage it from the Staff screen.',
        });

      await _pumpActivity(tester, api);
      await _openRowMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot Edit Expense'), findsOneWidget);
      expect(find.textContaining('Staff screen'), findsOneWidget);
      expect(find.text('Edit Expense'), findsNothing);
      expect(api.putCalls, isEmpty);
    });

    testWidgets('Delete confirms first, then DELETEs', (tester) async {
      final api = FakeApiClient()
        ..stubGet(_dashPath(), _dashboard())
        ..stubDelete('/expenses/77', {'expenseId': 77});

      await _pumpActivity(tester, api);
      await _openRowMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Expense?'), findsOneWidget);
      expect(api.deleteCalls, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, ['/expenses/77']);
    });

    testWidgets('cancelling the delete confirmation sends nothing',
        (tester) async {
      final api = FakeApiClient()..stubGet(_dashPath(), _dashboard());

      await _pumpActivity(tester, api);
      await _openRowMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, isEmpty);
    });
  });

  group('Expenses landing page', () {
    testWidgets('shows total / categories / insights but no rows',
        (tester) async {
      final api = FakeApiClient()..stubGet(_dashPath(), _dashboard());
      final state = AppState(apiClient: api)
        ..initialized = true
        ..isLoggedIn = true
        ..roleTypeId = 'OWNER';

      await pumpDataScreen(
        tester,
        const ExpensesScreen(propertyId: 9, propertyName: 'Sunrise PG'),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.text('Category Overview'), findsOneWidget);
      // The row-by-row sections moved to ExpenseActivityScreen.
      expect(find.text('Pending Expenses'), findsNothing);
      expect(find.text('Transactions'), findsOneWidget); // the chip, not a list
      expect(find.text('Vegetables'), findsNothing);
      expect(find.text('Plumber visit'), findsNothing);
      // Approvals chip carries the pending count.
      expect(find.text('Approvals'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the Approvals chip opens the activity screen on Pending',
        (tester) async {
      final api = FakeApiClient()..stubGet(_dashPath(), _dashboard());
      final state = AppState(apiClient: api)
        ..initialized = true
        ..isLoggedIn = true
        ..roleTypeId = 'OWNER';

      await pumpDataScreen(
        tester,
        const ExpensesScreen(propertyId: 9, propertyName: 'Sunrise PG'),
        state: state,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approvals'));
      await tester.pumpAndSettle();

      expect(find.text('Expense Activity'), findsOneWidget);
      expect(find.text('Plumber visit'), findsOneWidget);
      // Month header is present and fixed above the pager.
      expect(find.text(DateFormat('MMMM yyyy').format(DateTime.now())),
          findsOneWidget);
    });

    testWidgets('swiping the pager moves between Pending and Transactions',
        (tester) async {
      final api = FakeApiClient()..stubGet(_dashPath(), _dashboard());
      await _pumpActivity(tester, api, page: 0);

      expect(find.text('Plumber visit'), findsOneWidget);
      expect(find.text('Vegetables'), findsNothing);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Vegetables'), findsOneWidget);
      expect(find.text('Plumber visit'), findsNothing);
    });

    /// Regression: reloading used to swap the pager for a skeleton, which
    /// detached the PageController; it then restored to its initialPage while
    /// the highlighted tab still pointed at the swiped-to page.
    testWidgets('refresh keeps the visible page and the highlighted tab in step',
        (tester) async {
      final api = FakeApiClient()..stubGet(_dashPath(), _dashboard());
      // Entered on Pending, then swiped to Transactions.
      await _pumpActivity(tester, api, page: 0);
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Vegetables'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();

      // Still on Transactions, not bounced back to Pending.
      expect(find.text('Vegetables'), findsOneWidget);
      expect(find.text('Plumber visit'), findsNothing);

      // And the same in the other direction: enter on Transactions, swipe back.
      await _pumpActivity(tester, api, page: 1);
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Plumber visit'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Plumber visit'), findsOneWidget);
      expect(find.text('Vegetables'), findsNothing);
    });
  });
}
