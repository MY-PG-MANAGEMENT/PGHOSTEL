import 'package:flutter/material.dart';

/// Lightweight, dependency-free shimmer used for loading skeletons.
///
/// A single [AnimationController] drives a moving gradient "sheen" across the
/// child via a [ShaderMask]. Wrap skeleton shapes ([SkeletonBox]) in one
/// [Skeleton] so they shimmer together in sync.
///
/// ```dart
/// Skeleton(child: Column(children: [SkeletonBox(height: 16, width: 120), ...]))
/// ```
class Skeleton extends StatefulWidget {
  const Skeleton({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// When false the child is shown as-is (no shimmer) — handy to flip a whole
  /// subtree between skeleton and real content without restructuring.
  final bool enabled;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    const base = Color(0xFFE9E7F2);
    const highlight = Color(0xFFF6F5FB);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value; // 0..1
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (t * 2 - 1); // sweep left → right
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// Slides a gradient horizontally by [dx] logical pixels (used by [Skeleton]).
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A single rounded placeholder block. Colour is irrelevant — the parent
/// [Skeleton]'s [ShaderMask] paints over it — but it must be opaque.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9E7F2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped skeleton row (avatar + two lines) matching the app's list cards.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({this.showLeading = true, super.key});

  final bool showLeading;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECF2)),
      ),
      child: Row(
        children: [
          if (showLeading) ...[
            const SkeletonBox(width: 44, height: 44, radius: 12),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 160, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 100, height: 11),
              ],
            ),
          ),
          const SkeletonBox(width: 48, height: 22, radius: 20),
        ],
      ),
    );
  }
}

/// A full-screen list of [SkeletonCard]s wrapped in one synced [Skeleton].
/// Drop this in a `FutureBuilder`'s waiting branch for a smooth loading feel.
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.count = 6, this.showLeading = true, this.padding, super.key});

  final int count;
  final bool showLeading;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: count,
        itemBuilder: (_, __) => SkeletonCard(showLeading: showLeading),
      ),
    );
  }
}
