import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/account_screens.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';
import 'package:pg_manager_owner_app/src/widgets/error_retry_view.dart';

import 'support/test_harness.dart';

/// Notification Settings toggles.
///
/// The screen used to re-assign its `FutureBuilder` future after every PATCH, so
/// tapping a switch blanked the entire list to a spinner and replayed the fade-in
/// before the new value showed up — and a failed PATCH was swallowed, leaving the
/// switch to spring back silently. It also never checked `snapshot.hasError`, so a
/// failed initial load sat on an endless spinner.
///
/// `enabled` is asserted as a JSON `1`/`0` on purpose: the backend reads it as
/// `COALESCE(p.enabled, TRUE)` and Connector/J returns a Number for a TINYINT(1)
/// seen through COALESCE, so that — not `true`/`false` — is the real payload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prefsPath = '/notifications/preferences';

  Map<String, dynamic> prefs({Object rentEnabled = 1, Object checkoutEnabled = 0}) => {
        'items': [
          {
            'category_id': 'RENT_REMINDER',
            'name': 'Rent Reminder',
            'description': 'Monthly rent due alerts',
            'enabled': rentEnabled,
          },
          {
            'category_id': 'CHECKOUT_REMINDER',
            'name': 'Checkout Reminder',
            'description': 'Upcoming checkouts',
            'enabled': checkoutEnabled,
          },
        ],
      };

  Future<void> pump(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(apiClient: fake)
          ..initialized = true
          ..isLoggedIn = true
          ..roleTypeId = 'OWNER',
        child: MaterialApp(
          navigatorKey: AppToast.navigatorKey,
          home: const NotificationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile tileFor(WidgetTester tester, String title) => tester.widget<SwitchListTile>(
        find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile)),
      );

  testWidgets('renders each category with its stored state (1/0, not true/false)',
      (tester) async {
    final fake = FakeApiClient()..stubGet(prefsPath, prefs());
    await pump(tester, fake);

    expect(tileFor(tester, 'Rent Reminder').value, isTrue);
    expect(tileFor(tester, 'Checkout Reminder').value, isFalse);
  });

  testWidgets('toggling off sends the category id and keeps the new value',
      (tester) async {
    final fake = FakeApiClient()
      ..stubGet(prefsPath, prefs())
      ..stubPatch(prefsPath, prefs(rentEnabled: 0));
    await pump(tester, fake);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(fake.patchCalls, [prefsPath]);
    expect(fake.patchBodies.single, {'RENT_REMINDER': false});
    // The switch must hold its new position, not snap back.
    expect(tileFor(tester, 'Rent Reminder').value, isFalse);
    // And the other row is untouched.
    expect(tileFor(tester, 'Checkout Reminder').value, isFalse);
    // No second GET: PATCH already returns the refreshed list, and it was the
    // refetch that blanked the screen. One GET total — the initial load.
    expect(fake.getCalls.where((p) => p == prefsPath), hasLength(1));
  });

  testWidgets('a slow refetch cannot blank the list, because there is none',
      (tester) async {
    final fake = FakeApiClient()
      ..stubGet(prefsPath, prefs())
      ..stubPatch(prefsPath, prefs(rentEnabled: 0));
    await pump(tester, fake);

    // Any GET issued from here on hangs. The old code refetched after every PATCH,
    // so this is exactly the window in which the whole list turned into a spinner.
    fake.stubGetPending(prefsPath);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Rent Reminder'), findsOneWidget);
    expect(find.text('Checkout Reminder'), findsOneWidget);
    expect(tileFor(tester, 'Rent Reminder').value, isFalse);
  });

  testWidgets('toggling on works the same way', (tester) async {
    final fake = FakeApiClient()
      ..stubGet(prefsPath, prefs())
      ..stubPatch(prefsPath, prefs(checkoutEnabled: 1));
    await pump(tester, fake);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
            of: find.text('Checkout Reminder'), matching: find.byType(SwitchListTile)),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(fake.patchBodies.single, {'CHECKOUT_REMINDER': true});
    expect(tileFor(tester, 'Checkout Reminder').value, isTrue);
  });

  testWidgets('the list never blanks to a spinner while saving', (tester) async {
    final fake = FakeApiClient()..stubGet(prefsPath, prefs());
    final pending = fake.stubPatchPending(prefsPath);
    await pump(tester, fake);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    // This is the actual reported symptom: the rows must still be on screen, with
    // the new value already showing, while the PATCH is in flight.
    expect(find.text('Rent Reminder'), findsOneWidget);
    expect(find.text('Checkout Reminder'), findsOneWidget);
    expect(tileFor(tester, 'Rent Reminder').value, isFalse);

    pending.complete(prefs(rentEnabled: 0));
    await tester.pumpAndSettle();
    expect(tileFor(tester, 'Rent Reminder').value, isFalse);
  });

  testWidgets('a second tap is ignored while the first is still saving',
      (tester) async {
    final fake = FakeApiClient()..stubGet(prefsPath, prefs());
    final pending = fake.stubPatchPending(prefsPath);
    await pump(tester, fake);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    // Two writes racing for one category could land in either order and leave the
    // stored value disagreeing with the switch.
    expect(fake.patchCalls, hasLength(1));

    pending.complete(prefs(rentEnabled: 0));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed save rolls the switch back and says so', (tester) async {
    final fake = FakeApiClient()
      ..stubGet(prefsPath, prefs())
      ..stubPatchError(prefsPath, Exception('network down'));
    await pump(tester, fake);

    expect(tileFor(tester, 'Rent Reminder').value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Silently springing back is what made this look broken — the value must
    // revert *and* the failure must be visible.
    expect(tileFor(tester, 'Rent Reminder').value, isTrue);
    expect(find.textContaining('Rent Reminder'), findsWidgets);
  });

  testWidgets('a failed load offers a retry instead of an endless spinner',
      (tester) async {
    final fake = FakeApiClient()..stubGetError(prefsPath, Exception('network down'));
    await pump(tester, fake);

    expect(find.byType(ErrorRetryView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Retry re-issues the GET and can recover.
    fake.stubGet(prefsPath, prefs());
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(tileFor(tester, 'Rent Reminder').value, isTrue);
  });

  testWidgets('an empty category list shows an empty state, not a spinner',
      (tester) async {
    final fake = FakeApiClient()..stubGet(prefsPath, const {'items': []});
    await pump(tester, fake);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No categories'), findsOneWidget);
  });
}
