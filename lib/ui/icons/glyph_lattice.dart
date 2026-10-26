import 'package:fl_clash/ui/icons/glyph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_parsing/path_parsing.dart';

/// The Tailscale mark: a lattice of nine dots, four of them solid and five of
/// them rings.
///
/// The geometry is the published path rather than a redrawing of it, because
/// the mark has to stay the official one. It is split into its dots so a fill
/// can close the rings in turn: a lattice has no strokes to fatten, so that is
/// what filling means here.
///
/// [fill] is drawn as given rather than animated here, so the caller that owns
/// the transition, [AnimatedGlyph], is the only thing moving it.
class GlyphLattice extends StatelessWidget {
  const GlyphLattice({
    super.key,
    required this.fill,
    this.size,
    this.color,
    this.opacity = 1,
    this.matchTextDirection = false,
  });

  /// How filled the mark is, from 0 for the published lattice to 1 for every
  /// dot solid.
  final double fill;
  final double? size;
  final Color? color;
  final double opacity;
  final bool matchTextDirection;

  /// A stroke glyph inks about four fifths of the grid while the mark fills all
  /// of it, so it is drawn smaller to sit at the same weight beside them.
  static const inkShare = 0.88;

  /// The published `d` of `assets/images/services/tailscale.svg`. A test holds
  /// the two equal, so the asset stays the source and this stays faithful.
  static const path =
      'M24 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'm-9 9a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'm0-9a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'm6-6a3 3 0 1 1 0-6 3 3 0 0 1 0 6z'
      'm0-.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z'
      'M3 24a3 3 0 1 1 0-6 3 3 0 0 1 0 6z'
      'm0-.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z'
      'm18 .5a3 3 0 1 1 0-6 3 3 0 0 1 0 6z'
      'm0-.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z'
      'M6 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'm9-9a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'm-3 2.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z'
      'M6 3a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'
      'M3 5.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z';

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final ink = color ?? iconTheme.color ?? const Color(0xFF000000);
    final side = size ?? iconTheme.size ?? Glyph.size;
    final mark = SizedBox.square(
      dimension: side,
      child: Center(
        child: CustomPaint(
          size: Size.square(side * inkShare),
          painter: GlyphLatticePainter(
            fill: fill.clamp(0, 1),
            color: ink.withValues(alpha: ink.a * opacity),
          ),
        ),
      ),
    );
    if (matchTextDirection && Directionality.of(context) == TextDirection.rtl) {
      return Transform.flip(flipX: true, child: mark);
    }
    return mark;
  }
}

/// One dot of the lattice, with the ring that hollows it out when it has one.
class _Dot {
  const _Dot({required this.outer, this.hole, required this.center});

  final Path outer;
  final Path? hole;
  final Offset center;
}

class GlyphLatticePainter extends CustomPainter {
  GlyphLatticePainter({required this.fill, required this.color});

  final double fill;
  final Color color;

  static final _dots = _parseDots();

  /// How many dots are hollow, which is how many steps a fill has.
  static int get hollowCount => _dots.where((dot) => dot.hole != null).length;

  /// The published path is a run of circles, and a ring is a circle followed by
  /// a smaller one at the same centre. Pairing them that way keeps this to the
  /// published geometry instead of a redrawing of it.
  static List<_Dot> _parseDots() {
    final circles = [
      for (final path in _subpathsOf(GlyphLattice.path))
        (path: path, bounds: path.getBounds()),
    ];
    // A ring is an outer circle with a smaller one inside it at the same centre.
    // Pairing them this way keeps the dots to the published geometry, so the
    // mark is the official one rather than a redrawing of it.
    final holes = <Path, Path>{};
    for (final outer in circles) {
      for (final inner in circles) {
        if (identical(inner.path, outer.path) ||
            inner.bounds.width >= outer.bounds.width) {
          continue;
        }
        if ((inner.bounds.center - outer.bounds.center).distance < 0.01) {
          holes[outer.path] = inner.path;
          break;
        }
      }
    }
    final dots = [
      for (final circle in circles)
        if (!holes.containsValue(circle.path))
          _Dot(
            outer: circle.path,
            hole: holes[circle.path],
            center: circle.bounds.center,
          ),
    ];
    // The middle lights first and the rest follow outward, so a fill reads as
    // spreading from the centre rather than as a scan line.
    const center = Offset(12, 12);
    dots.sort((a, b) {
      final near = (a.center - center).distance.compareTo(
        (b.center - center).distance,
      );
      return near != 0 ? near : a.center.dx.compareTo(b.center.dx);
    });
    return dots;
  }

  static List<Path> _subpathsOf(String data) {
    final writer = _SubpathWriter();
    writeSvgPathDataToPath(data, writer);
    return writer.paths;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / Glyph.size;
    final ink = Paint()..color = color;
    final clear = Paint()..blendMode = BlendMode.clear;
    final rings = _dots.where((dot) => dot.hole != null).toList();
    canvas.save();
    canvas.scale(scale);
    // The holes are cut from the mark's own layer, so they never reach what is
    // painted behind it.
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, Glyph.size, Glyph.size),
      Paint(),
    );
    for (final dot in _dots) {
      canvas.drawPath(dot.outer, ink);
      final hole = dot.hole;
      if (hole == null) {
        continue;
      }
      // A ring closes as its own hole shrinks, so the last dot to light is the
      // last one still open.
      final order = rings.indexOf(dot);
      final kept = (1 - (fill * rings.length - order)).clamp(0.0, 1.0);
      if (kept <= 0) {
        continue;
      }
      if (kept >= 1) {
        canvas.drawPath(hole, clear);
        continue;
      }
      canvas.save();
      canvas.translate(dot.center.dx, dot.center.dy);
      canvas.scale(kept);
      canvas.translate(-dot.center.dx, -dot.center.dy);
      canvas.drawPath(hole, clear);
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlyphLatticePainter oldDelegate) =>
      fill != oldDelegate.fill || color != oldDelegate.color;
}

/// Collects each subpath of a `d` string as its own [Path], because the mark is
/// made of separate dots rather than one outline.
class _SubpathWriter implements PathProxy {
  final paths = <Path>[];
  Path? _current;

  Path get _path {
    final current = _current;
    if (current != null) {
      return current;
    }
    final path = Path();
    paths.add(path);
    return _current = path;
  }

  @override
  void moveTo(double x, double y) {
    // A move begins the next dot, so the path before it is left as it is.
    _current = null;
    _path.moveTo(x, y);
  }

  @override
  void lineTo(double x, double y) => _path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => _path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => _path.close();
}
