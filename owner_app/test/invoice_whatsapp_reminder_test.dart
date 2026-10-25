import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/billing_screen.dart';
import 'package:pg_manager_owner_app/src/utils/whatsapp_link.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';
import 'package:pg_manager_owner_app/src/widgets/whatsapp_icon.dart';

import 'support/test_harness.dart';

/// Phase 1 WhatsApp reminders: the icon on [InvoiceDetailSheet] builds a `wa.me` deep link
/// from the server-supplied reminder and opens WhatsApp. The owner presses Send.
///
/// The app decides nothing about the message — reminder type, wording, amount and recipient
/// all arrive on the invoice-detail payload. So these tests mostly prove two things: that the
/// exact `wa.me` URL handed to the launcher is right (including encoding), and that the app
/// never claims a message was sent.
void main() {
  // url_launcher goes through a platform channel that does not exist in a widget test.
  // Mocking it is what lets us assert the URL instead of launching anything.
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  late List<String> launched;
  late bool launchSucceeds;

  setUp(() {
    launched = [];
    launchSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method == 'launch') {
        launched.add('${call.arguments['url']}');
        return launchSucceeds;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });

  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  Map<String, dynamic> invoice({num paid = 0, String status = 'PENDING'}) => {
        'invoice_id': 99,
        'invoice_month': '2026-08-01',
        'due_date': '2026-08-08',
        'total_amount': 8500,
        'paid_amount': paid,
        'balance': 8500 - paid,
        'status': status,
        'full_name': 'Ravi Kumar',
      };

  /// The server's reminder block, exactly as `GET /billing/invoices/{id}` returns it.
  Map<String, dynamic> reminder({
    bool canRemind = true,
    String status = 'DUE',
    String? blockedReason,
    String? whatsappNumber = '919876543210',
    String? message = 'Hi Ravi Kumar 👋\n\n'
        'A gentle reminder that your Monthly Rent at Sri Lakshmi PG is due today.\n\n'
        '🧾 Payment: Monthly Rent\n'
        '📅 Due date: 08-Aug-2026\n'
        '⏳ Status: Due today\n'
        '💰 Amount due: ₹8,500\n\n'
        'Paying today keeps your account clear. ✅\n\n'
        'Sri Lakshmi PG · PG Manager',
  }) =>
      {
        'status': status,
        'canRemind': canRemind,
        'blockedReason': blockedReason,
        'tenantName': 'Ravi Kumar',
        'propertyName': 'Sri Lakshmi PG',
        'paymentType': 'Monthly Rent',
        'dueAmount': 8500,
        'dueDate': '2026-08-08',
        'whatsappNumber': whatsappNumber,
        'message': message,
      };

  FakeApiClient detailFake({Map<String, dynamic>? reminderBlock}) => FakeApiClient()
    ..stubGet('/billing/invoices/99', {
      'items': [
        {'invoice_item_id': 1, 'item_type_id': 'MONTHLY_RENT', 'amount': 8500},
      ],
      if (reminderBlock != null) 'reminder': reminderBlock,
    });

  Future<void> pumpSheet(
    WidgetTester tester,
    FakeApiClient fake,
    Map<String, dynamic> inv,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // AppToast resolves its overlay through this navigatorKey; without it the
    // "Opening WhatsApp…" and error toasts are silently dropped.
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: ownerState(fake),
        child: MaterialApp(
          navigatorKey: AppToast.navigatorKey,
          home: Scaffold(
            body: InvoiceDetailSheet(invoice: inv, onRefresh: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final whatsappButton = find.ancestor(
    of: find.byType(WhatsAppIcon),
    matching: find.byType(IconButton),
  );

  IconButton button(WidgetTester tester) => tester.widget<IconButton>(whatsappButton);

  group('the wa.me link builder', () {
    test('carries the number and the percent-encoded message', () {
      final uri = whatsAppChatUri('919876543210', 'Hello Ravi');

      expect(uri.toString(), 'https://wa.me/919876543210?text=Hello%20Ravi');
    });

    /// Spaces must be %20, not '+'. wa.me does not reliably read '+' back as a space, so a
    /// form-encoded query arrives full of plus signs in the tenant's chat.
    test('encodes spaces as %20 rather than plus', () {
      final uri = whatsAppChatUri('919876543210', 'a b c');

      expect(uri.toString(), contains('%20'));
      expect(uri.toString(), isNot(contains('+')));
    });

    test('encodes newlines, the rupee sign and URL-significant characters', () {
      final uri = whatsAppChatUri('919876543210', 'A&B / C+D\n₹8,500');
      final query = uri!.toString().split('?text=').last;

      expect(query, contains('%0A')); // newline
      expect(query, contains('%E2%82%B9')); // ₹
      expect(query, contains('%26')); // &  — must not start a second query param
      expect(query, contains('%2F')); // /
      expect(query, contains('%2B')); // +  — must not be read back as a space
      // Decoding must return exactly what went in: encoded once, never twice.
      expect(Uri.decodeComponent(query), 'A&B / C+D\n₹8,500');
    });

    test('strips any punctuation left on the number', () {
      expect(whatsAppChatUri('+91 98765-43210', 'hi').toString(),
          startsWith('https://wa.me/919876543210?'));
    });

    /// Returns null rather than a bare wa.me URL: that would open WhatsApp's contact picker,
    /// and the owner could message the wrong person believing it was the tenant.
    test('refuses a missing number', () {
      expect(whatsAppChatUri(null, 'hi'), isNull);
      expect(whatsAppChatUri('', 'hi'), isNull);
      expect(whatsAppChatUri('---', 'hi'), isNull);
    });
  });

  group('the icon', () {
    testWidgets('is enabled once the server says a reminder can be sent', (tester) async {
      await pumpSheet(tester, detailFake(reminderBlock: reminder()), invoice());

      expect(whatsappButton, findsOneWidget);
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('is disabled, not hidden, for a fully paid invoice', (tester) async {
      await pumpSheet(
        tester,
        detailFake(
            reminderBlock: reminder(
                canRemind: false,
                status: 'SETTLED',
                blockedReason: 'This invoice is fully paid — there is nothing to remind about.',
                message: null)),
        invoice(paid: 8500, status: 'PAID'),
      );

      expect(whatsappButton, findsOneWidget);
      expect(button(tester).onPressed, isNull);
      // The tooltip is the server's sentence, so the app never guesses at the reason.
      expect(button(tester).tooltip, 'This invoice is fully paid — there is nothing to remind about.');
    });

    testWidgets('is disabled when the tenant has no usable number', (tester) async {
      await pumpSheet(
        tester,
        detailFake(
            reminderBlock: reminder(
                canRemind: false,
                blockedReason: 'WhatsApp number is not available for this tenant.',
                whatsappNumber: null,
                message: null)),
        invoice(),
      );

      expect(button(tester).onPressed, isNull);
      expect(button(tester).tooltip, 'WhatsApp number is not available for this tenant.');
    });

    testWidgets('is absent for a cancelled invoice', (tester) async {
      await pumpSheet(tester, detailFake(reminderBlock: reminder()),
          invoice(status: 'CANCELLED'));

      expect(whatsappButton, findsNothing);
    });

    testWidgets('is absent when the server sent no reminder block', (tester) async {
      await pumpSheet(tester, detailFake(), invoice());

      expect(whatsappButton, findsNothing);
    });

    testWidgets('is absent when the detail fetch fails', (tester) async {
      final fake = FakeApiClient()
        ..stubGetError('/billing/invoices/99', Exception('offline'));

      await pumpSheet(tester, fake, invoice());

      expect(whatsappButton, findsNothing);
    });
  });

  group('tapping it', () {
    testWidgets('opens WhatsApp on the tenant chat with the reminder pre-filled',
        (tester) async {
      await pumpSheet(tester, detailFake(reminderBlock: reminder()), invoice());
      await tester.tap(whatsappButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(launched, hasLength(1));
      final uri = Uri.parse(launched.single);
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      // The message is the server's, delivered verbatim — the app composes nothing.
      final text = uri.queryParameters['text']!;
      expect(text, startsWith('Hi Ravi Kumar 👋'));
      expect(text, contains('is due today'));
      expect(text, contains('₹8,500'));
      // The emoji line markers must survive the round trip through percent-encoding, or the
      // tenant reads a message full of escape sequences.
      expect(text, contains('🧾 Payment: Monthly Rent'));
      expect(text, endsWith('Sri Lakshmi PG · PG Manager'));
    });

    /// The app hands off to WhatsApp and cannot know whether Send was pressed. Claiming
    /// delivery would let an owner believe a tenant was chased when they were not.
    testWidgets('says it is opening WhatsApp, never that a message was sent',
        (tester) async {
      await pumpSheet(tester, detailFake(reminderBlock: reminder()), invoice());
      await tester.tap(whatsappButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Opening WhatsApp'), findsOneWidget);
      expect(find.textContaining('Sent'), findsNothing);
      expect(find.textContaining('sent'), findsNothing);
    });

    testWidgets('reports a device with no WhatsApp installed', (tester) async {
      launchSucceeds = false;

      await pumpSheet(tester, detailFake(reminderBlock: reminder()), invoice());
      await tester.tap(whatsappButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('WhatsApp is not installed'), findsOneWidget);
    });

    testWidgets('a paid invoice cannot launch anything', (tester) async {
      await pumpSheet(
        tester,
        detailFake(
            reminderBlock: reminder(
                canRemind: false, status: 'SETTLED', blockedReason: 'paid', message: null)),
        invoice(paid: 8500, status: 'PAID'),
      );
      // Disabled, so the tap does not reach the handler at all.
      await tester.tap(whatsappButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(launched, isEmpty);
    });

    /// The reminder arrives with the invoice, so there is no fetch on tap and therefore no
    /// spinner — one tap, straight to WhatsApp.
    testWidgets('makes no extra API call', (tester) async {
      final fake = detailFake(reminderBlock: reminder());

      await pumpSheet(tester, fake, invoice());
      final before = fake.getCalls.length;
      await tester.tap(whatsappButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fake.getCalls.length, before);
      expect(fake.postCalls, isEmpty);
      expect(launched, hasLength(1));
    });
  });
}
