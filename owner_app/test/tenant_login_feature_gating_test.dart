import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/account_screens.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';

import 'support/test_harness.dart';

/// Tenant Login is opt-in per organization and controlled only by the super admin
/// (Admin → Messaging → tap an org → Tenant Login switch). The owner side must
/// follow that flag exactly: "Generate Tenant Logins" appears in Settings when the
/// org has it ON and is completely absent when it is OFF.
///
/// The behaviour existed but nothing asserted it, so a refactor of the Settings
/// screen could have silently started showing a feature the org cannot use — or
/// hiding one it pays for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeApiClient settingsFake({required Object loginFeature}) {
    final fake = FakeApiClient();
    // The Settings screen loads notification preferences on open.
    fake.stubGet('/account/preferences', const {'items': []});
    if (loginFeature is Map<String, dynamic>) {
      fake.stubGet('/tenants/login-feature', loginFeature);
    } else {
      fake.stubGetError('/tenants/login-feature', loginFeature);
    }
    return fake;
  }

  Future<void> pumpSettings(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(900, 2400);
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
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('toggle ON shows Generate Tenant Logins', (tester) async {
    final fake = settingsFake(loginFeature: const {'enabled': true});
    await pumpSettings(tester, fake);

    expect(find.text('Tenant Portal'), findsOneWidget);
    expect(find.text('Generate Tenant Logins'), findsOneWidget);
    expect(fake.getCalls, contains('/tenants/login-feature'));
  });

  testWidgets('toggle OFF hides the whole Tenant Portal group', (tester) async {
    final fake = settingsFake(loginFeature: const {'enabled': false});
    await pumpSettings(tester, fake);

    // Not merely disabled — absent. A greyed-out control would still advertise a
    // feature the organization has not been granted.
    expect(find.text('Generate Tenant Logins'), findsNothing);
    expect(find.text('Tenant Portal'), findsNothing);
  });

  testWidgets('a missing enabled flag is treated as OFF', (tester) async {
    final fake = settingsFake(loginFeature: const {});
    await pumpSettings(tester, fake);

    // The feature is opt-in, so anything short of an explicit true stays hidden.
    expect(find.text('Generate Tenant Logins'), findsNothing);
  });

  testWidgets('a non-boolean enabled value is treated as OFF', (tester) async {
    final fake = settingsFake(loginFeature: const {'enabled': 'yes'});
    await pumpSettings(tester, fake);

    // `data['enabled'] == true` is an identity check, not a truthiness check.
    expect(find.text('Generate Tenant Logins'), findsNothing);
  });

  testWidgets('a failed feature probe fails closed, not open', (tester) async {
    final fake = settingsFake(loginFeature: Exception('network down'));
    await pumpSettings(tester, fake);

    // Failing open would offer an action the backend will reject anyway, so the
    // probe is best-effort and the group stays hidden.
    expect(find.text('Generate Tenant Logins'), findsNothing);
    // And the rest of Settings still renders — one dead probe must not blank it.
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('the rest of Settings is unaffected when the group is hidden', (tester) async {
    final fake = settingsFake(loginFeature: const {'enabled': false});
    await pumpSettings(tester, fake);

    expect(find.text('Generate Tenant Logins'), findsNothing);
    // Sanity: the screen really did build its other groups, so the assertions
    // above are about the gate and not about an empty screen.
    expect(find.byType(ListTile), findsWidgets);
  });
}
