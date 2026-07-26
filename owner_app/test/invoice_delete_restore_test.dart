import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/billing_screen.dart';

import 'support/test_harness.dart';

/// Covers invoice delete/restore in [InvoiceDetailSheet]. Delete is a reversible
/// soft-cancel offered **only** for a pending invoice, and the Restore action lives
/// in the same sheet the owner just deleted from — so the undo is where they are
/// looking, not buried on another screen.
void main() {
  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  Map<String, dynamic> invoice(String status, {num paid = 0}) => {
        'invoice_id': 99,
        'invoice_month': '2026-07-01',
        'due_date': '2026-07-05',
        'total_amount': 8000,
        'paid_amount': paid,
        'balance': 8000 - paid,
        'status': status,
        'full_name': 'Asha Rao',
      };

  FakeApiClient invoiceFake() => FakeApiClient()
    ..stubGet('/billing/invoices/99', {
      'items': [
        {'invoice_item_id': 1, 'item_type_id': 'MONTHLY_RENT', 'amount': 8000},
      ],
    });

  Future<void> pumpSheet(
    WidgetTester tester,
    FakeApiClient fake,
    Map<String, dynamic> inv, {
    VoidCallback? onRefresh,
  }) async {
    await pumpDataScreen(
      tester,
      Scaffold(
        body: InvoiceDetailSheet(
          invoice: inv,
          onRefresh: onRefresh ?? () {},
        ),
      ),
      state: ownerState(fake),
    );
    await tester.pumpAndSettle();
  }

  final deleteIcon = find.widgetWithIcon(IconButton, Icons.delete_outline);
  final restoreButton = find.widgetWithText(FilledButton, 'Restore Invoice');

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  group('delete is offered only for a pending invoice', () {
    testWidgets('a pending invoice shows both edit and delete', (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('PENDING'));

      expect(deleteIcon, findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('an overdue invoice offers neither delete nor restore',
        (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('OVERDUE'));

      expect(deleteIcon, findsNothing);
      expect(restoreButton, findsNothing);
      // Chasing it is still the point of the sheet.
      expect(find.textContaining('Collect Payment'), findsOneWidget);
    });

    testWidgets('a part-paid invoice cannot be deleted', (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('PARTIAL', paid: 3000));

      expect(deleteIcon, findsNothing);
    });

    testWidgets('a paid invoice cannot be deleted', (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('PAID', paid: 8000));

      expect(deleteIcon, findsNothing);
    });
  });

  group('deleting a pending invoice', () {
    testWidgets('calls DELETE and swaps the sheet over to Restore',
        (tester) async {
      final fake = invoiceFake()..stubDelete('/billing/invoices/99');
      var refreshed = 0;

      await pumpSheet(tester, fake, invoice('PENDING'),
          onRefresh: () => refreshed++);
      await confirmDelete(tester);

      expect(fake.deleteCalls, ['/billing/invoices/99']);
      // The sheet stays open on the now-cancelled invoice so the undo is right here.
      expect(restoreButton, findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(deleteIcon, findsNothing);
      expect(find.textContaining('Collect Payment'), findsNothing);
      // The list behind the sheet has to drop it out of the pending totals.
      expect(refreshed, 1);
    });

    testWidgets('the confirmation promises the invoice can be restored',
        (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('PENDING'));
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.textContaining('restore it'), findsOneWidget);
    });

    testWidgets('a rejected delete leaves the invoice pending', (tester) async {
      final fake = invoiceFake()
        ..stubDeleteError('/billing/invoices/99',
            Exception('Only a pending invoice can be deleted'));

      await pumpSheet(tester, fake, invoice('PENDING'));
      await confirmDelete(tester);

      expect(restoreButton, findsNothing);
      expect(deleteIcon, findsOneWidget);
    });
  });

  group('restoring', () {
    testWidgets('a cancelled invoice opened from the list offers Restore',
        (tester) async {
      await pumpSheet(tester, invoiceFake(), invoice('CANCELLED'));

      expect(restoreButton, findsOneWidget);
      expect(deleteIcon, findsNothing);
      // A cancelled invoice is not a due — collecting against it makes no sense.
      expect(find.textContaining('Collect Payment'), findsNothing);
    });

    testWidgets('Restore posts to the restore endpoint and returns to pending',
        (tester) async {
      final fake = invoiceFake()
        ..stubPost('/billing/invoices/99/restore', {'status': 'PENDING'});
      var refreshed = 0;

      await pumpSheet(tester, fake, invoice('CANCELLED'),
          onRefresh: () => refreshed++);
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();

      expect(fake.postCalls, ['/billing/invoices/99/restore']);
      expect(restoreButton, findsNothing);
      expect(find.textContaining('Collect Payment'), findsOneWidget);
      expect(refreshed, 1);
    });

    testWidgets('a failed restore keeps the invoice cancelled', (tester) async {
      final fake = invoiceFake()
        ..stubPostError('/billing/invoices/99/restore', Exception('nope'));

      await pumpSheet(tester, fake, invoice('CANCELLED'));
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();

      expect(restoreButton, findsOneWidget);
    });
  });
}
