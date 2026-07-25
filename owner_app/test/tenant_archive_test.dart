import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/tenant_screen.dart';

import 'support/test_harness.dart';

/// Covers the "delete tenant" flow, which is an archive rather than a delete:
/// bulk-select on the Inactive list, and the Deleted Tenants screen that restores
/// them. Both must hit the archive endpoints — never a destructive one.
void main() {
  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  FakeApiClient tenantsFake() => FakeApiClient()
    ..stubGet('/tenants', {
      'items': [
        {
          'tenantId': 1,
          'fullName': 'Asha Rao',
          'mobileNumber': '9876543210',
          'hasActiveAdmission': true,
        },
        {
          'tenantId': 2,
          'fullName': 'Vikram Singh',
          'mobileNumber': '9123456780',
          'hasActiveAdmission': false,
        },
        {
          'tenantId': 3,
          'fullName': 'Left Long Ago',
          'mobileNumber': '9000000001',
          'hasActiveAdmission': false,
        },
      ],
    });

  /// The Inactive filter reveals a delete icon next to the chips; tapping it turns
  /// the list into a multi-select.
  Future<void> enterSelectMode(WidgetTester tester) async {
    await tester.tap(find.text('INACTIVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();
  }

  group('Inactive list bulk delete', () {
    testWidgets('selecting inactive tenants posts them to /tenants/archive',
        (tester) async {
      final fake = tenantsFake()..stubPost('/tenants/archive', {'archived': 2, 'skippedActive': 0});

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      await enterSelectMode(tester);

      expect(find.text('0 selected'), findsOneWidget);

      // Select both inactive tenants (the active one is not in this filter).
      await tester.tap(find.text('Vikram Singh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left Long Ago'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Confirmation spells out that the data survives.
      expect(find.text('Delete 2 tenants?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
      await tester.pumpAndSettle();

      expect(fake.postCalls, contains('/tenants/archive'));
      expect(fake.postBodies.last['partyIds'], [2, 3]);
    });

    testWidgets('cancelling the confirmation posts nothing', (tester) async {
      final fake = tenantsFake();

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      await enterSelectMode(tester);

      await tester.tap(find.text('Vikram Singh'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      // .last = the dialog's Cancel (the selection bar has one too).
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      expect(fake.postCalls, isEmpty);
      expect(find.text('1 selected'), findsOneWidget); // selection survives
    });

    testWidgets('the delete icon only appears on the Inactive list', (tester) async {
      final fake = tenantsFake();

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      // Default ACTIVE filter — nothing here can be deleted.
      expect(find.widgetWithIcon(IconButton, Icons.delete_outline), findsNothing);

      await tester.tap(find.text('All Tenants'));
      await tester.pumpAndSettle();
      expect(find.widgetWithIcon(IconButton, Icons.delete_outline), findsNothing);

      await tester.tap(find.text('INACTIVE'));
      await tester.pumpAndSettle();
      expect(find.widgetWithIcon(IconButton, Icons.delete_outline), findsOneWidget);
    });

    testWidgets('switching away from Inactive leaves select mode', (tester) async {
      final fake = tenantsFake();

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      await enterSelectMode(tester);
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text('ACTIVE'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsNothing);
    });

    testWidgets('Deleted tenants lives in the app bar menu, not the filter row',
        (tester) async {
      final fake = tenantsFake();

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Deleted tenants'), findsOneWidget);
      // Login generation moved to Settings.
      expect(find.text('Generate tenant logins'), findsNothing);
    });

    testWidgets('the property-scoped tab has no app bar menu', (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/properties/7/tenants', {'items': const []});

      // Mirrors how the property workspace embeds it: inside its own Scaffold.
      await pumpDataScreen(tester, const Scaffold(body: TenantScreen(propertyId: 7)),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('Tenant detail single delete', () {
    Map<String, dynamic> inactiveTenant() => {
          'tenantId': 2,
          'fullName': 'Vikram Singh',
          'mobileNumber': '9123456780',
          'hasActiveAdmission': false,
        };

    testWidgets('the Profile tab delete button sends DELETE /tenants/{id}',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/tenants/2', inactiveTenant())
        ..stubDelete('/tenants/2', {'archived': 1});

      await pumpDataScreen(tester, TenantDetailScreen(tenant: inactiveTenant()),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      // On the screen itself, not behind the overflow menu.
      expect(find.text('Delete this tenant'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Tenant'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Tenant?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fake.deleteCalls, contains('/tenants/2'));
    });

    testWidgets('the overflow menu no longer carries Delete', (tester) async {
      final fake = FakeApiClient()..stubGet('/tenants/2', inactiveTenant());

      await pumpDataScreen(tester, TenantDetailScreen(tenant: inactiveTenant()),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      // Scoped to menu entries: the Profile tab's own Delete button is still in the
      // tree behind the open menu.
      expect(find.widgetWithText(PopupMenuItem<String>, 'Delete Tenant'), findsNothing);
    });

    testWidgets('an active tenant gets Checkout, not Delete', (tester) async {
      final active = {...inactiveTenant(), 'hasActiveAdmission': true};
      final fake = FakeApiClient()..stubGet('/tenants/2', active);

      await pumpDataScreen(tester, TenantDetailScreen(tenant: active),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('Checkout Tenant'), findsOneWidget);
      expect(find.text('Delete this tenant'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Delete Tenant'), findsNothing);
    });
  });

  group('ArchivedTenantsScreen', () {
    testWidgets('lists deleted tenants and restores one', (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/tenants/archived', {
          'items': [
            {
              'tenantId': 42,
              'fullName': 'Vikram Singh',
              'mobileNumber': '9123456780',
              'propertyName': 'Sunrise PG',
              'archivedAt': '2026-07-01T10:00:00',
              'lastCheckoutDate': '2026-06-28',
            },
          ],
        })
        ..stubPost('/tenants/42/restore', {'tenantId': 42});

      await pumpDataScreen(tester, const ArchivedTenantsScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('Vikram Singh'), findsOneWidget);
      expect(find.textContaining('Sunrise PG'), findsOneWidget);
      expect(find.textContaining('Deleted 01-07-2026'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(fake.postCalls, contains('/tenants/42/restore'));
    });

    testWidgets('property-scoped entry filters the request and the restore',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/tenants/archived?propertyId=7', {'items': const []});

      await pumpDataScreen(tester, const ArchivedTenantsScreen(propertyId: 7),
          state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(fake.getCalls, contains('/tenants/archived?propertyId=7'));
      expect(find.text('No deleted tenants'), findsOneWidget);
    });
  });
}
