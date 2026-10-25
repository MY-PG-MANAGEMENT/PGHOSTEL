import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/billing_screen.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';
import 'package:pg_manager_owner_app/src/widgets/whatsapp_icon.dart';

import 'support/test_harness.dart';

/// The invoice sheet packs a header, three labelled actions, a four-value metric strip, a charge
/// breakdown and two money cells into a bottom sheet. Both the header and the metric strip reflow
/// below 460 px, so the widths below are the two sides of that breakpoint plus a small phone —
/// `takeException` is what catches a RenderFlex overflow, which no other test would notice.
void main() {
  for (final size in [const Size(360, 780), const Size(430, 932), const Size(820, 1180)]) {
    testWidgets('lays out with no overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = FakeApiClient()
        ..stubGet('/billing/invoices/99', {
          'items': [
            {'invoice_item_id': 1, 'item_type_id': 'MONTHLY_RENT', 'amount': 6000},
            {'invoice_item_id': 2, 'item_type_id': 'AC_CHARGES', 'amount': 500},
            {'invoice_item_id': 3, 'item_type_id': 'SECURITY_DEPOSIT', 'amount': 10000},
          ],
          'reminder': {
            'status': 'DUE',
            'canRemind': true,
            'whatsappNumber': '919876543210',
            'message': 'hi',
          },
        });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: AppState(apiClient: fake)
            ..initialized = true
            ..isLoggedIn = true
            ..roleTypeId = 'OWNER',
          child: MaterialApp(
            navigatorKey: AppToast.navigatorKey,
            home: Scaffold(
              body: InvoiceDetailSheet(
                invoice: const {
                  'invoice_id': 99,
                  'invoice_number': 'INV-JUL-2026-0012',
                  'invoice_month': '2026-07-01',
                  'due_date': '2026-07-20',
                  'total_amount': 16500,
                  'paid_amount': 0,
                  'balance': 16500,
                  'status': 'PENDING',
                  'full_name': 'Rahul Kumar',
                },
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Invoice #INV-JUL-2026-0012'), findsOneWidget);
      expect(find.text('Charge Details'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
      expect(find.textContaining('Collect Payment'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // The three actions sit on the title's own row at every width, never wrapped below it: a
      // right-aligned row of tiles under the title reads as a detached toolbar rather than as
      // this invoice's actions. Anchored on "Invoice", which never leaves that row — the
      // invoice *number* does drop to its own line on a narrow sheet, by design.
      //
      // Measured on each tile's icon, not its label: the tile is a two-line stack, so the label
      // legitimately sits a little below the title's baseline while the tile is still in the row.
      final title = tester.getRect(find.text('Invoice'));
      final icons = <String, Finder>{
        'WhatsApp': find.byType(WhatsAppIcon),
        'Edit': find.byIcon(Icons.edit_outlined),
        'Delete': find.byIcon(Icons.delete_outline),
      };
      icons.forEach((label, finder) {
        final rect = tester.getRect(finder);
        expect(rect.top, lessThan(title.bottom),
            reason: '$label wrapped below the title at $size');
        expect(rect.bottom, greaterThan(title.top),
            reason: '$label wrapped above the title at $size');
      });

      // …and all three share one row as each other.
      final tops =
          ['WhatsApp', 'Edit', 'Delete'].map((l) => tester.getRect(find.text(l)).top);
      expect(tops.toSet(), hasLength(1));

      // Whichever line it lands on, the number is never squeezed to an ellipsis-only stub.
      expect(tester.getRect(find.text('Invoice #INV-JUL-2026-0012')).width,
          greaterThan(120),
          reason: 'invoice number squeezed at $size');
    });
  }
}
