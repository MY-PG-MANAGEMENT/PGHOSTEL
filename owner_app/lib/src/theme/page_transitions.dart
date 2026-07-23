import 'package:flutter/material.dart';

/// App-wide page transition: the incoming route fades in while sliding up a few
/// pixels (a calm, modern "settle into place" motion); pop plays it in reverse.
///
/// Wired into [ThemeData.pageTransitionsTheme] via [smoothPageTransitionsTheme],
/// so it applies to **every** navigation — both `go_router` pages and any
/// `Navigator.push(MaterialPageRoute(...))` — from a single place. No per-screen
/// or per-route wiring needed.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // The page being covered fades back slightly for a gentle "fade-through" feel.
    final covering = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);

    return FadeTransition(
      opacity: entering,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(entering),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.92).animate(covering),
          child: child,
        ),
      ),
    );
  }
}

/// Applies [SmoothPageTransitionsBuilder] on every platform (mobile + web +
/// desktop) so screen changes feel identical everywhere.
const PageTransitionsTheme smoothPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: SmoothPageTransitionsBuilder(),
    TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
    TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
    TargetPlatform.windows: SmoothPageTransitionsBuilder(),
    TargetPlatform.linux: SmoothPageTransitionsBuilder(),
    TargetPlatform.fuchsia: SmoothPageTransitionsBuilder(),
  },
);
