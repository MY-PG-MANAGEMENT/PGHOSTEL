import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one notification style for the whole app.
///
/// Every operation outcome — success, error, info — is shown through
/// [AppToast] so the format is identical on every screen: a floating white
/// card with a tinted icon badge, a short bold title and the message. It
/// drops in from the **top** and renders in the root navigator overlay, so it
/// always appears **over** open bottom sheets and dialogs (a plain SnackBar
/// would slide in underneath them).
///
/// ```dart
/// AppToast.success(context, 'Bed assigned to Ramesh');
/// AppToast.error(context, 'Payment exceeds invoice balance');
/// ```
///
/// The `*Of` variants exist for call sites that pop a sheet/dialog first and
/// no longer have a usable context — they route through the same global
/// overlay, so the captured messenger is only kept for API compatibility:
/// ```dart
/// final messenger = ScaffoldMessenger.of(context);
/// Navigator.pop(context, true);
/// AppToast.successOf(messenger, 'Checkout completed');
/// ```
class AppToast {
  AppToast._();

  /// Wire this into the app router (`GoRouter(navigatorKey: AppToast.navigatorKey)`)
  /// so toasts can be inserted into the root overlay from anywhere, above any
  /// modal route that is currently open.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static OverlayEntry? _current;

  static void success(BuildContext context, String message, {String? title}) =>
      _show(message,
          title: title ?? 'Success',
          color: PgColors.success,
          icon: Icons.check_circle_rounded,
          context: context);

  static void error(BuildContext context, String message, {String? title}) =>
      _show(message,
          title: title ?? 'Something went wrong',
          color: PgColors.danger,
          icon: Icons.error_rounded,
          duration: const Duration(seconds: 4),
          context: context);

  static void info(BuildContext context, String message, {String? title}) =>
      _show(message,
          title: title ?? 'Info',
          color: PgColors.primary,
          icon: Icons.info_rounded,
          context: context);

  static void successOf(ScaffoldMessengerState messenger, String message,
          {String? title}) =>
      _show(message,
          title: title ?? 'Success',
          color: PgColors.success,
          icon: Icons.check_circle_rounded,
          context: messenger.context);

  static void errorOf(ScaffoldMessengerState messenger, String message,
          {String? title}) =>
      _show(message,
          title: title ?? 'Something went wrong',
          color: PgColors.danger,
          icon: Icons.error_rounded,
          duration: const Duration(seconds: 4),
          context: messenger.context);

  static void infoOf(ScaffoldMessengerState messenger, String message,
          {String? title}) =>
      _show(message,
          title: title ?? 'Info',
          color: PgColors.primary,
          icon: Icons.info_rounded,
          context: messenger.context);

  static void _show(
    String message, {
    required String title,
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 3),
    BuildContext? context,
  }) {
    // Prefer the global root overlay (renders above modal sheets/dialogs);
    // fall back to the nearest root overlay reachable from the given context.
    final overlay = navigatorKey.currentState?.overlay ??
        (context != null ? Overlay.maybeOf(context, rootOverlay: true) : null);
    if (overlay == null) return;

    // Only one toast at a time — replace whatever is showing.
    _current?.remove();
    _current = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastCard(
        message: message,
        title: title,
        color: color,
        icon: icon,
        duration: duration,
        onFinished: () {
          if (_current == entry) {
            entry.remove();
            _current = null;
          }
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.message,
    required this.title,
    required this.color,
    required this.icon,
    required this.duration,
    required this.onFinished,
  });

  final String message;
  final String title;
  final Color color;
  final IconData icon;
  final Duration duration;
  final VoidCallback onFinished;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with TickerProviderStateMixin {
  // Slide + fade for entry/exit.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutBack));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _slide, curve: Curves.easeOut);

  // Countdown that drives the bottom progress bar and auto-dismiss.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _progress.forward();
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _progress.stop();
    if (mounted) await _slide.reverse();
    widget.onFinished();
  }

  @override
  void dispose() {
    _slide.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final color = widget.color;
    // Opaque, gently tinted surface so the card never blends into the page.
    final surface = Color.alphaBlend(color.withValues(alpha: 0.07), Colors.white);

    return Positioned(
      top: topInset + 10,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: color.withValues(alpha: 0.55), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.22),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 12, 8, 12),
                        child: Row(
                          children: [
                            // Icon badge — the status symbol.
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(widget.icon,
                                  color: Colors.white, size: 23),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.title,
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          height: 1.1)),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.message,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: PgColors.textPrimary,
                                        fontSize: 12.5,
                                        height: 1.25),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkResponse(
                              onTap: _dismiss,
                              radius: 18,
                              child: Icon(Icons.close_rounded,
                                  size: 18,
                                  color: PgColors.textSecondary
                                      .withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                      // Countdown bar.
                      AnimatedBuilder(
                        animation: _progress,
                        builder: (_, __) => LinearProgressIndicator(
                          value: 1 - _progress.value,
                          minHeight: 3,
                          backgroundColor: color.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
