import 'package:flutter/material.dart';

/// Subtle entrance animation: fades in while sliding up a few pixels.
///
/// Wrap any widget to give it a clean, lightweight "appear" motion. Pass a
/// [delay] to stagger a list of items (e.g. `delay: Duration(milliseconds: 40 * index)`).
///
/// ```dart
/// FadeSlideIn(delay: Duration(milliseconds: 40 * i), child: MyCard())
/// ```
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 350),
    this.offset = 12,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical distance (logical px) the child travels up into place.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Continuously "breathes" its child by gently scaling it up and down on a
/// loop. Useful to draw attention to an actionable element such as the
/// fingerprint icon on the unlock button.
///
/// ```dart
/// const Pulse(child: Icon(Icons.fingerprint))
/// ```
class Pulse extends StatefulWidget {
  const Pulse({
    required this.child,
    this.duration = const Duration(milliseconds: 1100),
    this.minScale = 1.0,
    this.maxScale = 1.18,
    super.key,
  });

  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)
        ..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(
    begin: widget.minScale,
    end: widget.maxScale,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// Cross-fades between its children when [child] changes (e.g. loading → data).
/// A drop-in, gentler replacement for an abrupt state swap.
class FadeSwitcher extends StatelessWidget {
  const FadeSwitcher({
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}
