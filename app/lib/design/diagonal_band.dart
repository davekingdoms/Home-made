import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Decoration of the highlighted cards and of the hub cards: two diagonal
/// bands with rounded ends, across the end side of the card (sections 4 and
/// 8 of `docs/spec/stile.md`).
///
/// It fills the space it is given and paints inside it only; it has no
/// meaning for the screen reader.
class DiagonalBand extends StatelessWidget {
  const new({required this.color, super.key});

  /// Colour of the bands: `AppColors.banda` over `primaryContainer`.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _DiagonalBandPainter(color: color, mirrored: rtl),
        size: Size.infinite,
      ),
    );
  }
}

class _DiagonalBandPainter extends CustomPainter {
  const new({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  /// Slope of the bands, from the bottom towards the end side.
  static const double _angle = -math.pi / 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final thickness = size.shortestSide * 0.42;
    // Long enough to cross the card whatever its proportions.
    final length = size.longestSide * 2;

    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    if (mirrored) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    canvas
      ..translate(size.width * 0.82, size.height * 0.5)
      ..rotate(_angle);
    _band(canvas, paint, length, thickness, offset: -thickness * 0.2);
    _band(canvas, paint, length, thickness * 0.45, offset: thickness * 0.95);
    canvas.restore();
  }

  /// A band along the rotated axis, [offset] away from it, that starts at
  /// the centre and runs past the edge of the card.
  void _band(
    Canvas canvas,
    Paint paint,
    double length,
    double thickness, {
    required double offset,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          -thickness,
          offset - thickness / 2,
          length,
          thickness,
        ),
        Radius.circular(thickness / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DiagonalBandPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}
