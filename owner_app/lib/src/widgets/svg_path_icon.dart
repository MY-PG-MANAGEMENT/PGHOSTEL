import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

/// Paints a single-path SVG glyph.
///
/// The app has exactly one SVG (the WhatsApp mark on the tenant action row),
/// so it does not carry `flutter_svg` — that pulls in the whole
/// `vector_graphics` compiler (an XML parser plus an SVG optimiser) to render
/// one static path. `path_parsing` is the same path grammar `vector_graphics`
/// itself uses, so the geometry is byte-for-byte what it produced.
///
/// Layout matches `SvgPicture`'s defaults: the [viewBox] is scaled with
/// `BoxFit.contain`, centred in the widget box, and the path is filled with
/// the SVG non-zero rule and antialiasing on.
class SvgPathIcon extends StatelessWidget {
  const SvgPathIcon({
    super.key,
    required this.pathData,
    required this.color,
    required this.viewBox,
    required this.size,
  });

  /// The `d` attribute of the SVG `<path>`.
  final String pathData;

  /// The path's `fill`.
  final Color color;

  /// The source `viewBox` extent the [pathData] coordinates are expressed in.
  final Size viewBox;

  /// The box to paint into, in logical pixels.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: CustomPaint(
        painter: _SvgPathPainter(pathData: pathData, color: color, viewBox: viewBox),
      ),
    );
  }
}

class _SvgPathPainter extends CustomPainter {
  const _SvgPathPainter({
    required this.pathData,
    required this.color,
    required this.viewBox,
  });

  final String pathData;
  final Color color;
  final Size viewBox;

  /// Parsing is pure and the app's glyphs are compile-time constants, so the
  /// built [Path] is shared across every repaint and every list row.
  static final Map<String, Path> _parsed = <String, Path>{};

  @override
  void paint(Canvas canvas, Size size) {
    final path = _parsed.putIfAbsent(pathData, () {
      final builder = _PathBuilder();
      writeSvgPathDataToPath(pathData, builder);
      return builder.path;
    });

    final scale = math.min(size.width / viewBox.width, size.height / viewBox.height);
    canvas
      ..save()
      ..translate(
        (size.width - viewBox.width * scale) / 2,
        (size.height - viewBox.height * scale) / 2,
      )
      ..scale(scale)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_SvgPathPainter oldDelegate) =>
      oldDelegate.pathData != pathData ||
      oldDelegate.color != color ||
      oldDelegate.viewBox != viewBox;
}

class _PathBuilder extends PathProxy {
  final Path path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
