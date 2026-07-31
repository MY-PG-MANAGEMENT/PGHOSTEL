import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/screens/admin_screen.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';
import 'package:pg_manager_owner_app/src/widgets/home_back_handler.dart';

import 'support/test_harness.dart';

/// Back navigation in the super-admin console.
///
/// The sidebar sections are local state, not routes, so /admin is the only route
/// on the stack. Without a PopScope the system back button had nothing to pop and
/// closed the app from whichever section the admin was in, instead of returning
/// them to Dashboard.
///
/// `handlePopRoute()` is what the engine calls on a system back press: it returns
/// true when the framework handled the press, and false when it declined — the
/// case where the platform goes on to close the app. So the return value is the
/// assertion, not a proxy for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeApiClient adminFake() {
    final fake = FakeApiClient();
    fake.stubGet('/super-admin/dashboard', const {
      'totalOrganizations': 2,
      'activeOrganizations': 2,
      'totalProperties': 4,
      'totalTenants': 25,
      'monthlyRevenue': 0,
      'recentActivity': [],
    });
    fake.stubGet('/super-admin/organizations', const {
      'items': [
        {
          'organization_id': 1,
          'facility_name': 'Sunrise PG',
          'status': 'ACTIVE',
          'owner_name': 'Asha',
          'mobile_number': '9876500001',
        },
      ],
    });
    return fake;
  }

  /// Wide viewport so the >=900px sidebar is on screen and a section can be
  /// reached by tapping its label.
  Future<void> pumpAdmin(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(apiClient: fake)
          ..initialized = true
          ..isLoggedIn = true
          ..roleTypeId = 'SUPER_ADMIN',
        child: MaterialApp(
          navigatorKey: AppToast.navigatorKey,
          home: const SuperAdminScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The section is identified by its _PageHeader title. Both the sidebar item
  /// and the header carry the same string, so match on the header's text style
  /// (18px semi-bold) rather than the label alone.
  Finder sectionHeader(String title) => find.byWidgetPredicate(
        (w) => w is Text && w.data == title && (w.style?.fontSize ?? 0) >= 17,
      );

  testWidgets('back from a section returns to Dashboard instead of closing the app',
      (tester) async {
    await pumpAdmin(tester, adminFake());
    expect(sectionHeader('Dashboard'), findsOneWidget);

    await tester.tap(find.text('Organizations').last);
    await tester.pumpAndSettle();
    expect(sectionHeader('Organizations'), findsOneWidget);
    expect(sectionHeader('Dashboard'), findsNothing);

    // Handled by the framework — this is the press that used to close the app.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(sectionHeader('Dashboard'), findsOneWidget);
    expect(sectionHeader('Organizations'), findsNothing);
  });

  testWidgets('back from Dashboard bubbles to the platform', (tester) async {
    await pumpAdmin(tester, adminFake());
    expect(sectionHeader('Dashboard'), findsOneWidget);

    // Dashboard is the root of the console, so declining the press is correct:
    // the platform minimises/exits rather than the app trapping the user.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  /// As main.dart wires it: /admin is wrapped in HomeBackHandler, so the console
  /// carries two PopScopes at once — its own (section → Dashboard) and the global
  /// one (route → home). Every registered entry is notified on a declined pop, so
  /// this checks they cooperate: the section handler acts, and the global one must
  /// stay out of the way because /admin already *is* a super admin's home.
  Future<void> pumpRoutedAdmin(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (_, __) => const HomeBackHandler(child: SuperAdminScreen()),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Owner Dashboard')),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(apiClient: fake)
          ..initialized = true
          ..isLoggedIn = true
          ..roleTypeId = 'SUPER_ADMIN',
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with the global handler attached, back still only resets the section',
      (tester) async {
    await pumpRoutedAdmin(tester, adminFake());

    await tester.tap(find.text('Organizations').last);
    await tester.pumpAndSettle();
    expect(sectionHeader('Organizations'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(sectionHeader('Dashboard'), findsOneWidget);
    // The global handler must not have navigated anywhere: /admin is home.
    expect(find.text('Owner Dashboard'), findsNothing);

    // And from the console's Dashboard, back leaves for the platform.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('every section unwinds to Dashboard on back', (tester) async {
    await pumpAdmin(tester, adminFake());

    for (final label in ['Audit Logs', 'System Settings', 'Messaging']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(sectionHeader(label), findsOneWidget, reason: 'opened $label');

      expect(await tester.binding.handlePopRoute(), isTrue,
          reason: 'back from $label must be handled');
      await tester.pumpAndSettle();
      expect(sectionHeader('Dashboard'), findsOneWidget,
          reason: 'back from $label lands on Dashboard');
    }
  });
}
