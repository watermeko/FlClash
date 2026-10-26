import 'package:fl_clash/ui/icons/glyph.dart';
import 'package:fl_clash/ui/icons/glyph_lattice.dart';
import 'package:fl_clash/ui/icons/glyph_painter.dart';
import 'package:material_ui/material_ui.dart';

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.fill, this.size, this.color});

  final Glyph glyph;
  final double? fill;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = this.color ?? iconTheme.color!;
    final opacity = iconTheme.opacity ?? 1;
    final side = size ?? iconTheme.size ?? Glyph.size;
    if (glyph.lattice ?? false) {
      // A dot lattice fills by closing its rings, so it takes the same fill
      // the stroke glyphs do and draws it its own way.
      return GlyphLattice(
        fill: fill ?? iconTheme.fill ?? 0,
        size: side,
        color: color,
        opacity: opacity,
        matchTextDirection: glyph.matchTextDirection,
      );
    }
    final icon = SizedBox.square(
      dimension: side,
      child: Center(
        child: CustomPaint(
          size: Size.square(side),
          painter: GlyphPainter(
            glyph: glyph,
            fill: fill ?? iconTheme.fill ?? 0,
            color: color.withValues(alpha: color.a * opacity),
          ),
        ),
      ),
    );
    if (glyph.matchTextDirection &&
        Directionality.of(context) == TextDirection.rtl) {
      return Transform.flip(flipX: true, child: icon);
    }
    return icon;
  }
}
