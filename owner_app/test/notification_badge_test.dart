import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/responsive_modules.dart';

import 'support/test_harness.dart';

/// The unread dot on the dashboard notification bell.
///
/// It was a hardcoded `Container` inside the bell's `Stack` — painted on every
/// build, driven by nothing at all — so it stayed lit no matter how many
/// notifications were read. It is now gated on a real unread count.
///
/// There is no dedicated count endpoint; the notifications list reports `total`
/// per filter, so `state=UNREAD&size=1` is the count with a one-row payload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const unreadPath = '/notifications?state=UNREAD&size=1';

  FakeApiClient dashboardFake({Object? unread = 3}) {
    final fake = FakeApiClient();
    fake.stubGet('/owner/dashboard', const {
      'totalProperties': 1,
      'totalTenants': 4,
      'occupiedBeds': 4,
      'vacantBeds': 2,
      'monthlyRevenue': 40000,
      'pendingDues': 0,
    });
    // Empty property list keeps the per-property stats fetches out of this test.
    fake.stubGet('/owner/properties', const {'items': []});
    if (unread is Map<String, dynamic>) {
      fake.stubGet(unreadPath, unread);
    } else if (unread is int) {
      fake.stubGet(unreadPath, {'items': const [], 'total': unread});
    } else {
      fake.stubGetError(unreadPath, Exception('network down'));
    }
    return fake;
  }

  Future<void> pumpDashboard(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const PgDashboardScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('Notifications')),
            body: const Center(child: Text('notifications route')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(apiClient: fake)
          ..initialized = true
          ..isLoggedIn = true
          ..roleTypeId = 'OWNER'
          ..ownerName = 'Asha Rao',
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The dot is the only 9x9 red circle in the bell's Stack.
  Finder dot() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == const Color(0xFFEF4444);
      });

  testWidgets('shows the dot while notifications are unread', (tester) async {
    final fake = dashboardFake(unread: 3);
    await pumpDashboard(tester, fake);

    expect(dot(), findsOneWidget);
    expect(fake.getCalls, contains(unreadPath));
  });

  testWidgets('no dot when nothing is unread', (tester) async {
    await pumpDashboard(tester, dashboardFake(unread: 0));

    // The whole reported bug: read everything and the mark must go.
    expect(dot(), findsNothing);
  });

  testWidgets('the dot clears on return from the notifications screen',
      (tester) async {
    final fake = dashboardFake(unread: 2);
    await pumpDashboard(tester, fake);
    expect(dot(), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('notifications route'), findsOneWidget);

    // Everything got read while the user was in there.
    fake.stubGet(unreadPath, {'items': const [], 'total': 0});

    // Back out — the count must be re-taken, not trusted from before.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('notifications route'), findsNothing);
    expect(dot(), findsNothing);
  });

  testWidgets('a still-unread count keeps the dot after returning',
      (tester) async {
    final fake = dashboardFake(unread: 2);
    await pumpDashboard(tester, fake);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    // Re-counting must not be mistaken for clearing.
    expect(dot(), findsOneWidget);
  });

  testWidgets('a failed count hides the dot and leaves the dashboard usable',
      (tester) async {
    await pumpDashboard(tester, dashboardFake(unread: null));

    // Failing open would restore exactly the bug being fixed: a mark nobody can
    // clear. The dashboard itself must still render, since the count is a
    // separate request from the dashboard payload.
    expect(dot(), findsNothing);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('a missing total is treated as nothing unread', (tester) async {
    await pumpDashboard(tester, dashboardFake(unread: const {'items': []}));

    expect(dot(), findsNothing);
  });
}
