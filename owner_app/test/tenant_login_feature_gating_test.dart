import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/account_screens.dart';
import 'package:pg_manager_owner_app/src/screens/property_workspace_screen.dart';
import 'package:pg_manager_owner_app/src/utils/tenant_login_feature.dart';
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

  // ── Property workspace → Quick Actions → Complaints ────────────────────────
  //
  // Complaints are raised by tenants through the portal, so the quick action can
  // only ever lead to an empty list for an org whose Tenant Login is off. It
  // follows the same super-admin flag as the Settings group above, via the shared
  // fetchTenantLoginEnabled probe.
  group('Complaints quick action', () {
    FakeApiClient workspaceFake({required Object loginFeature}) {
      final fake = FakeApiClient();
      fake.stubGet('/properties/7/stats', const {
        'totalRooms': 4,
        'totalBeds': 12,
        'occupiedBeds': 9,
        'vacantBeds': 3,
        'activeTenants': 9,
        'monthlyRevenue': 90000,
        'pendingDues': 0,
      });
      // The workspace body is an IndexedStack, so all four tabs mount at once and
      // their fetches must be stubbed even though only Overview is asserted on.
      fake.stubGet('/properties/7/tenants', const {'items': []});
      fake.stubGet('/billing/dashboard?propertyId=7', const {});
      fake.stubGet('/billing/invoices?propertyId=7', const {'items': []});
      if (loginFeature is Map<String, dynamic>) {
        fake.stubGet('/tenants/login-feature', loginFeature);
      } else {
        fake.stubGetError('/tenants/login-feature', loginFeature);
      }
      return fake;
    }

    Future<void> pumpWorkspace(WidgetTester tester, FakeApiClient fake) async {
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
            home: const PropertyWorkspaceScreen(
              property: {'facilityId': 7, 'facilityName': 'Sunrise PG'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('toggle ON shows Complaints in Quick Actions', (tester) async {
      final fake = workspaceFake(loginFeature: const {'enabled': true});
      await pumpWorkspace(tester, fake);

      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Complaints'), findsOneWidget);
      expect(fake.getCalls, contains('/tenants/login-feature'));
    });

    testWidgets('toggle OFF hides Complaints', (tester) async {
      await pumpWorkspace(tester, workspaceFake(loginFeature: const {'enabled': false}));

      // Absent, not disabled — a greyed-out card would still advertise a feature
      // the organization has not been granted.
      expect(find.text('Complaints'), findsNothing);
      // The other quick actions must survive the gate, so this is about the one
      // card and not about a grid that failed to build.
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Floors & Rooms'), findsOneWidget);
      expect(find.text('Temporary Stay'), findsOneWidget);
    });

    testWidgets('a failed probe hides Complaints but leaves the tab working',
        (tester) async {
      await pumpWorkspace(tester, workspaceFake(loginFeature: Exception('network down')));

      expect(find.text('Complaints'), findsNothing);
      // The probe is deliberately separate from the stats future: a dead probe
      // must not take the Overview tab down with it.
      expect(find.text('Floors & Rooms'), findsOneWidget);
    });

    testWidgets('a missing or non-boolean flag is treated as OFF', (tester) async {
      await pumpWorkspace(tester, workspaceFake(loginFeature: const {}));
      expect(find.text('Complaints'), findsNothing);

      await pumpWorkspace(tester, workspaceFake(loginFeature: const {'enabled': 'yes'}));
      expect(find.text('Complaints'), findsNothing);
    });
  });

  // The shared probe both gates use. Tested directly so the contract is pinned
  // even if either screen is restyled.
  group('fetchTenantLoginEnabled', () {
    Future<bool> probe(Object response) async {
      final fake = FakeApiClient();
      if (response is Map<String, dynamic>) {
        fake.stubGet('/tenants/login-feature', response);
      } else {
        fake.stubGetError('/tenants/login-feature', response);
      }
      return fetchTenantLoginEnabled(fake);
    }

    test('true only for an explicit enabled:true', () async {
      expect(await probe(const {'enabled': true}), isTrue);
      expect(await probe(const {'enabled': false}), isFalse);
      expect(await probe(const {}), isFalse);
      expect(await probe(const {'enabled': 'yes'}), isFalse);
      expect(await probe(const {'enabled': 1}), isFalse);
    });

    test('fails closed instead of throwing', () async {
      expect(await probe(Exception('network down')), isFalse);
    });
  });
}
