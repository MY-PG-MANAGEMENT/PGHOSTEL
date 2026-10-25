import 'package:flutter/widgets.dart';

import 'svg_path_icon.dart';

/// The official WhatsApp brand mark.
///
/// Lived privately in `tenant_screen.dart` while the tenant action row was the only
/// place that needed it. The invoice reminder button is the second, so it moved here
/// rather than being copied — two copies of a 1.5 KB path string are two chances for
/// them to drift, and the brand colour must match exactly wherever it appears.
///
/// The path itself is the `d` of the FontAwesome WhatsApp glyph; [SvgPathIcon] fills it,
/// so no asset, no network request and no `flutter_svg` dependency is involved.
const Size kWhatsAppViewBox = Size(448, 512);

/// WhatsApp's brand green. Also the correct tint for a "send on WhatsApp" affordance —
/// this is the one place in the app that deliberately steps outside [PgColors].
const Color kWhatsAppGreen = Color(0xFF25D366);

/// A pale green that reads as a tinted icon-button background against white.
const Color kWhatsAppSurface = Color(0xFFD9F7E3);

const String kWhatsAppPath =
    'M380.9 97.1C339 55.1 283.2 32 223.9 32c-122.4 0-222 99.6-222 222 0 39.1 '
    '10.2 77.3 29.6 111L0 480l117.7-30.9c32.4 17.7 68.9 27 106.1 27h.1c122.3 0 224.1-99.6 224.1-222 '
    '0-59.3-25.2-115-67.2-157zm-157 341.6c-33.2 0-65.7-8.9-94-25.7l-6.7-4-69.8 18.3L72 359.2l-4.4-7c-18.5-29.4-28.2-63.3-28.2-98.2 '
    '0-101.7 82.8-184.5 184.6-184.5 49.3 0 95.6 19.2 130.4 54.1 34.8 34.9 56.2 81.2 56.1 130.5 0 101.8-84.9 184.6-186.6 184.6zm101.2-138.2c-5.5-2.8-32.8-16.2-37.9-18-5.1-1.9-8.8-2.8-12.5 '
    '2.8-3.7 5.6-14.3 18-17.6 21.8-3.2 3.7-6.5 4.2-12 1.4-32.6-16.3-54-29.1-75.5-66-5.7-9.8 5.7-9.1 '
    '16.3-30.3 1.8-3.7.9-6.9-.5-9.7-1.4-2.8-12.5-30.1-17.1-41.2-4.5-10.8-9.1-9.3-12.5-9.5-3.2-.2-6.9-.2-10.6-.2-3.7 '
    '0-9.7 1.4-14.8 6.9-5.1 5.6-19.4 19-19.4 46.3 0 27.3 19.9 53.7 22.6 57.4 2.8 3.7 39.1 59.7 94.8 '
    '83.8 35.2 15.2 49 16.5 66.6 13.9 10.7-1.6 32.8-13.4 37.4-26.4 4.6-13 4.6-24.1 3.2-26.4-1.3-2.5-5-3.9-10.5-6.6z';

/// The WhatsApp mark at [size], in [color] (brand green by default).
///
/// Pass a muted [color] for a disabled affordance — the glyph is a filled path, so
/// wrapping it in [Opacity] would also fade whatever sits behind it.
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({super.key, this.size = 22, this.color = kWhatsAppGreen});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPathIcon(
        pathData: kWhatsAppPath,
        color: color,
        viewBox: kWhatsAppViewBox,
        size: Size(size, size),
      );
}
