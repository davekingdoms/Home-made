import 'dart:math' as math;

import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// The "biscotto": a circle with twelve rounded lobes, for avatars and
/// counters (sections 4 and 8 of `docs/spec/stile.md`).
class CookieBorder extends OutlinedBorder {
  const new({super.side});

  /// Number of lobes around the circle.
  static const int lobes = 12;

  /// How deep the hollows between two lobes are, as a fraction of the radius.
  static const double depth = 0.1;

  /// Points drawn for each lobe.
  static const int _pointsPerLobe = 16;

  Path _cookie(Rect rect) {
    final center = rect.center;
    final radius = rect.shortestSide / 2;
    const points = lobes * _pointsPerLobe;
    final path = Path();
    for (var i = 0; i < points; i++) {
      final angle = 2 * math.pi * i / points;
      // 1 on the tip of a lobe, 1 - depth at the bottom of a hollow.
      final r = radius * (1 - depth * (1 - math.cos(lobes * angle)) / 2);
      final point = center + Offset(math.sin(angle), -math.cos(angle)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _cookie(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _cookie(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    // The stroke is centred on the path it follows.
    final inset = side.strokeInset - side.width / 2;
    canvas.drawPath(_cookie(rect.deflate(inset)), side.toPaint());
  }

  @override
  CookieBorder copyWith({BorderSide? side}) =>
      CookieBorder(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => CookieBorder(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is CookieBorder
      ? CookieBorder(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is CookieBorder
      ? CookieBorder(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CookieBorder &&
      other.side == side;

  @override
  int get hashCode => side.hashCode;
}

/// Avatar of a member on a cookie: the first letter of the name over the
/// subdued accent.
class CookieAvatar extends StatelessWidget {
  const new({required this.name, this.size = AppSizes.listAvatar, super.key});

  /// Name of the member: its first letter is shown, the whole name is read
  /// by the screen reader.
  final String name;

  /// 48 in the hub, 40 in the lists.
  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final initial = name.isEmpty ? '' : name.characters.first.toUpperCase();
    return _Cookie(
      size: size,
      semanticLabel: name,
      text: initial,
      style: textTheme.titleMedium,
    );
  }
}

/// Counter on a cookie, such as the number of transactions to classify.
class CookieCounter extends StatelessWidget {
  const new({
    required this.count,
    required this.semanticLabel,
    this.size = AppSizes.listAvatar,
    super.key,
  });

  final int count;

  /// What the number counts, read by the screen reader: for example
  /// "8 transazioni da classificare".
  final String semanticLabel;

  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Cookie(
      size: size,
      semanticLabel: semanticLabel,
      text: '$count',
      style: textTheme.titleMedium?.amount,
    );
  }
}

class _Cookie extends StatelessWidget {
  const new({
    required this.size,
    required this.semanticLabel,
    required this.text,
    required this.style,
  });

  final double size;
  final String semanticLabel;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.tertiary,
            shape: const CookieBorder(),
          ),
          child: Padding(
            padding: EdgeInsets.all(size / 5),
            // The cookie does not grow with the text: the text shrinks to fit.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: style?.copyWith(color: scheme.onTertiary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
