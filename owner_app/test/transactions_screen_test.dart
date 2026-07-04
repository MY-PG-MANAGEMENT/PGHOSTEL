import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/transactions_screen.dart';

import 'support/test_harness.dart';

void main() {
  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  final now = DateTime.now();
  final thisMonth =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final path = '/transactions?propertyId=5&month=$thisMonth';

  final ledger = {
    'month': thisMonth,
    'summary': {
      'totalIn': 12000,
      'totalOut': 4500,
      'net': 7500,
      'countIn': 1,
      'countOut': 1,
    },
    'items': [
      {
        'type': 'IN',
        'id': 11,
        'title': 'Asha Rao',
        'category': null,
        'amount': 12000,
        'method': 'UPI',
        'date': '2026-07-04',
      },
      {
        'type': 'OUT',
        'id': 7,
        'title': 'Electricity Bill',
        'category': 'ELECTRICITY',
        'amount': 4500,
        'method': 'CASH',
        'date': '2026-07-03',
      },
    ],
  };

  group('TransactionsScreen', () {
    testWidgets('renders summary and both ledger entries', (tester) async {
      final fake = FakeApiClient()..stubGet(path, ledger);

      await pumpDataScreen(
          tester,
          const TransactionsScreen(propertyId: 5, propertyName: 'Sunrise PG'),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('Sunrise PG'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Electricity Bill'), findsOneWidget);
      expect(find.text('+₹12,000'), findsOneWidget); // summary MONEY IN
      expect(find.text('-₹4,500'), findsOneWidget); // summary MONEY OUT
      expect(find.text('+₹7,500'), findsOneWidget); // summary NET
    });

    testWidgets('negative net renders a single minus sign', (tester) async {
      final fake = FakeApiClient()
        ..stubGet(path, {
          'month': thisMonth,
          'summary': {
            'totalIn': 1000,
            'totalOut': 5000,
            'net': -4000,
            'countIn': 1,
            'countOut': 1,
          },
          'items': const [],
        });

      await pumpDataScreen(
          tester,
          const TransactionsScreen(propertyId: 5, propertyName: 'Sunrise PG'),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('-₹4,000'), findsOneWidget);
      expect(find.text('--₹4,000'), findsNothing);
    });

    testWidgets('In/Out filter chips narrow the ledger', (tester) async {
      final fake = FakeApiClient()..stubGet(path, ledger);

      await pumpDataScreen(
          tester,
          const TransactionsScreen(propertyId: 5, propertyName: 'Sunrise PG'),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Money In'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Electricity Bill'), findsNothing);

      await tester.tap(find.text('Money Out'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Rao'), findsNothing);
      expect(find.text('Electricity Bill'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Electricity Bill'), findsOneWidget);
    });

    testWidgets('month switcher fetches the selected month', (tester) async {
      final prev = DateTime(now.year, now.month - 1);
      final prevPath =
          '/transactions?propertyId=5&month=${prev.year}-${prev.month.toString().padLeft(2, '0')}';
      final fake = FakeApiClient()
        ..stubGet(path, ledger)
        ..stubGet(prevPath, {
          'month': 'prev',
          'summary': {'totalIn': 0, 'totalOut': 0, 'net': 0},
          'items': const [],
        });

      await pumpDataScreen(
          tester,
          const TransactionsScreen(propertyId: 5, propertyName: 'Sunrise PG'),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(fake.getCalls, contains(prevPath));
      expect(find.text('Asha Rao'), findsNothing);
      expect(find.textContaining('No transactions in'), findsOneWidget);
    });
  });
}
