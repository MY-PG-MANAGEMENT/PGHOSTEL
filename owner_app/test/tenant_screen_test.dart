import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/tenant_screen.dart';
import 'package:pg_manager_owner_app/src/widgets/error_retry_view.dart';

import 'support/test_harness.dart';

void main() {
  // Builds an AppState wired to [fake] and primed as an initialised, logged-in
  // owner — the conditions TenantScreen assumes when it issues its GET /tenants.
  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  group('TenantScreen', () {
    testWidgets('loading state shows a progress indicator while the fetch is pending',
        (tester) async {
      final fake = FakeApiClient();
      final pending = fake.stubGetPending('/tenants');

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      // Deliberately do NOT settle — the future is still pending.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(fake.getCalls, contains('/tenants'));

      // Release the future so the test can tear down cleanly.
      pending.complete({'items': const []});
      await tester.pumpAndSettle();
    });

    testWidgets('data state renders a tenant card with name and mobile',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGet('/tenants', {
          'items': [
            {
              'tenantId': 1,
              'fullName': 'Asha Rao',
              'mobileNumber': '9876543210',
              'hasActiveAdmission': true,
              'currentRoomName': 'Room 101',
              'currentBedName': 'Bed A',
            },
            {
              'tenantId': 2,
              'fullName': 'Vikram Singh',
              'mobileNumber': '9123456780',
              'hasActiveAdmission': false,
            },
          ],
        });

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Vikram Singh'), findsOneWidget);
      // Active/Inactive badges from _ActiveBadge.
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      // No empty/error chrome when data is present.
      expect(find.text('No tenants found'), findsNothing);
      expect(find.byType(ErrorRetryView), findsNothing);
    });

    testWidgets('error state shows ErrorRetryView with a Try Again button',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGetError('/tenants', Exception('Boom'));

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorRetryView), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('error state retry re-issues the GET and can recover to data',
        (tester) async {
      final fake = FakeApiClient()
        ..stubGetError('/tenants', Exception('Boom'));

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
      final callsAfterError = fake.getCalls.length;

      // Next fetch should succeed.
      fake.stubGet('/tenants', {
        'items': [
          {'tenantId': 9, 'fullName': 'Recovered Tenant', 'mobileNumber': '9000000000'},
        ],
      });

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(fake.getCalls.length, greaterThan(callsAfterError));
      expect(find.text('Recovered Tenant'), findsOneWidget);
      expect(find.byType(ErrorRetryView), findsNothing);
    });

    testWidgets('empty state shows the "No tenants found" message',
        (tester) async {
      final fake = FakeApiClient()..stubGet('/tenants', {'items': const []});

      await pumpDataScreen(tester, const TenantScreen(), state: ownerState(fake));
      await tester.pumpAndSettle();

      expect(find.text('No tenants found'), findsOneWidget);
      expect(find.text('Register tenants to track occupancy and payments.'),
          findsOneWidget);
      // Empty-with-no-query offers an Add Tenant CTA.
      expect(find.widgetWithText(FilledButton, 'Add Tenant'), findsOneWidget);
    });
  });
}
