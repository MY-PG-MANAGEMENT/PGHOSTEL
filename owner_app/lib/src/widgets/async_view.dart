import 'package:flutter/material.dart';

import 'error_retry_view.dart';
import 'loading_view.dart';
import 'skeleton.dart';

/// One place for the loading → data / error flow every data screen repeats.
///
/// Wraps a [FutureBuilder] and cross-fades ([AnimatedSwitcher]) between three
/// states so screens never "pop" between a spinner and content:
///  - **waiting** → a shimmer [SkeletonList] (or a custom [loading] widget, or a
///    plain [LoadingView] when `skeleton: false`);
///  - **error**   → [ErrorRetryView] wired to [onRetry];
///  - **data**    → your [builder].
///
/// ```dart
/// AsyncView<Map<String, dynamic>>(
///   future: _future,
///   onRetry: _reload,
///   builder: (context, data) => MyContent(data),
/// )
/// ```
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.future,
    required this.builder,
    this.onRetry,
    this.loading,
    this.skeleton = true,
    this.skeletonCount = 6,
    this.skeletonLeading = true,
    this.duration = const Duration(milliseconds: 300),
    super.key,
  });

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;

  /// Called by the error view's "Try Again" button. Strongly recommended.
  final VoidCallback? onRetry;

  /// Custom loading widget. Defaults to a [SkeletonList] (or [LoadingView] when
  /// [skeleton] is false).
  final Widget? loading;
  final bool skeleton;
  final int skeletonCount;
  final bool skeletonLeading;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        final Widget child;
        final String state;
        if (snap.connectionState == ConnectionState.waiting) {
          state = 'loading';
          child = loading ??
              (skeleton
                  ? SkeletonList(count: skeletonCount, showLeading: skeletonLeading)
                  : const LoadingView());
        } else if (snap.hasError) {
          state = 'error';
          child = ErrorRetryView(error: snap.error!, onRetry: onRetry ?? () {});
        } else {
          state = 'data';
          child = builder(context, snap.data as T);
        }
        return AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          // Fade + a whisper of upward motion as content settles in.
          transitionBuilder: (widget, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
              child: widget,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(key: ValueKey(state), child: child),
        );
      },
    );
  }
}
