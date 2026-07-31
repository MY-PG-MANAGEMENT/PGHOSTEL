import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/widgets/home_back_handler.dart';

import 'support/test_harness.dart';

/// System-back behaviour on menu destinations.
///
/// The app's signed-in routes are flat top-level GoRoutes and the menus navigate
/// with `context.go`, which replaces the stack instead of pushing onto it. So on
/// any menu destination there was nothing to pop, the framework declined the back
/// press, and the platform closed the app instead of returning the user to their
/// dashboard. [HomeBackHandler] is the shared fix, applied to every signed-in
/// route in main.dart.
///
/// `handlePopRoute()` is exactly what the engine calls on a system back press: it
/// returns true when the framework handled it and false when it declined — the
/// case where the platform goes on to close the app. The return value is the
/// assertion, not a proxy for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mirrors main.dart's shape: flat top-level routes, each wrapped in the
  /// handler, reached by `go` (stack-replacing) and drilled into by `push`.
  Widget app(AppState state, {String initial = '/dashboard'}) {
    Widget page(String label) => HomeBackHandler(
          child: Scaffold(body: Center(child: Text(label))),
        );

    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => page('Dashboard')),
        GoRoute(path: '/properties', builder: (_, __) => page('Properties')),
        GoRoute(path: '/settings', builder: (_, __) => page('Settings')),
        GoRoute(path: '/settings/profile', builder: (_, __) => page('Profile')),
        GoRoute(path: '/admin', builder: (_, __) => page('Admin')),
        GoRoute(path: '/tenant', builder: (_, __) => page('Tenant Home')),
      ],
    );
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  AppState owner() => AppState(apiClient: FakeApiClient())
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  testWidgets('back on a menu destination goes home, not out of the app',
      (tester) async {
    await tester.pumpWidget(app(owner(), initial: '/properties'));
    await tester.pumpAndSettle();
    expect(find.text('Properties'), findsOneWidget);

    // The press that used to close the app.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Properties'), findsNothing);
  });

  testWidgets('back on the home route bubbles to the platform', (tester) async {
    await tester.pumpWidget(app(owner()));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);

    // Declining is correct at the root: the platform minimises/exits rather than
    // the app trapping the user on their own dashboard.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('a pushed drill-down still pops to where it was opened from',
      (tester) async {
    await tester.pumpWidget(app(owner(), initial: '/settings'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('Settings'));
    GoRouter.of(ctx).push('/settings/profile');
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    // Must land back on Settings — the handler has to leave a real pop alone
    // rather than shortcutting to the dashboard.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('home is role-aware', (tester) async {
    // A super admin's home is /admin, so back from a menu destination must not
    // drop them on the owner dashboard (the router would only bounce them back).
    await tester.pumpWidget(
      app(owner()..roleTypeId = 'SUPER_ADMIN', initial: '/properties'),
    );
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);

    await tester.pumpWidget(
      app(owner()..roleTypeId = 'TENANT', initial: '/properties'),
    );
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Tenant Home'), findsOneWidget);
  });

  testWidgets('a tenant on their own home route exits rather than looping',
      (tester) async {
    await tester.pumpWidget(
      app(owner()..roleTypeId = 'TENANT', initial: '/tenant'),
    );
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  test('homeRouteFor maps each role to its landing route', () {
    expect(homeRouteFor('SUPER_ADMIN'), '/admin');
    expect(homeRouteFor('TENANT'), '/tenant');
    expect(homeRouteFor('OWNER'), '/dashboard');
    expect(homeRouteFor('PROPERTY_MANAGER'), '/dashboard');
    // Unknown/absent role must still resolve — a null home would make the
    // handler navigate nowhere and swallow the press.
    expect(homeRouteFor(null), '/dashboard');
  });
}
