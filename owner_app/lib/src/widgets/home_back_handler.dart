import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// The route a signed-in user belongs on, per role.
///
/// Shared by `main.dart`'s router redirect and [HomeBackHandler] so the two can
/// never disagree about where "home" is — the redirect sending a role somewhere
/// the back handler does not recognise as home would trap the user in a loop.
String homeRouteFor(String? roleTypeId) => switch (roleTypeId) {
      'SUPER_ADMIN' => '/admin',
      'TENANT' => '/tenant',
      _ => '/dashboard',
    };

/// Makes the system back button behave on menu destinations.
///
/// Every signed-in screen is a flat top-level `GoRoute`, and the menus navigate
/// with `context.go`, which *replaces* the stack rather than pushing onto it. So
/// on any destination reached from a menu there was nothing to pop, the framework
/// declined the back press, and the platform closed the app — instead of taking
/// the user back to their dashboard.
///
/// The three cases, in the order they are decided:
///  * the router can pop (an imperatively pushed screen sits on top) — let it pop
///    normally, so drill-downs are untouched;
///  * we are already on the role's home route — let the press reach the platform
///    (minimise / exit), which is correct for the root of the app rather than
///    trapping the user;
///  * otherwise — intercept and go home.
///
/// An open drawer needs no special case: `Scaffold` registers a
/// `LocalHistoryEntry` for it, and local history is consulted before any
/// `PopScope`, so back closes the drawer and leaves the destination alone.
///
/// A screen may add its own [PopScope] on top of this one for internal state
/// (the admin console resets its selected section that way). Every registered
/// entry is notified, so both run: the route does not pop while either one says
/// it should not, and each handler only acts on what it owns.
class HomeBackHandler extends StatelessWidget {
  const HomeBackHandler({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    final home = homeRouteFor(
        context.select<AppState, String?>((s) => s.roleTypeId));
    final atHome = GoRouterState.of(context).uri.path == home;

    return PopScope(
      canPop: router.canPop() || atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !atHome) router.go(home);
      },
      child: child,
    );
  }
}
