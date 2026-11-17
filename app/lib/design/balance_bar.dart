import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Bar of a balance, split in the middle: a credit grows to the right in
/// `credito`, a debt to the left in `debito`, over a
/// `surfaceContainerHighest` track (sections 2.2 and 8 of
/// `docs/spec/stile.md`).
///
/// The colour is never the only signal: [amount] always carries its sign and
/// [label] says in words who owes. Every value arrives ready to show.
class BalanceBar extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    required this.amount,
    super.key,
  }) : assert(
         value >= -1 && value <= 1,
         'The value is a fraction of half the bar',
       );

  /// How much of its half the bar fills: from 0 to 1 for a credit, from 0 to
  /// -1 for a debt.
  final double value;

  /// Who owes, in words: for example "Devi tu" or "Deve alla casa".
  final String label;

  /// The amount with its sign, already formatted.
  final String amount;

  /// Height of the bar.
  static const double barHeight = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.appColors;
    final color = value < 0 ? colors.debito : colors.credito;
    return Semantics(
      label: '$label, $amount',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xs,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                amount,
                style: theme.textTheme.bodyLarge?.listAmount.copyWith(
                  color: value == 0 ? scheme.onSurface : color,
                ),
              ),
            ],
          ),
          SizedBox(
            height: barHeight,
            child: CustomPaint(
              painter: _BalanceBarPainter(
                value: value,
                color: color,
                trackColor: scheme.surfaceContainerHighest,
                centerColor: scheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceBarPainter extends CustomPainter {
  const new({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.centerColor,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final Color centerColor;

  /// Width of the mark in the middle.
  static const double _centerWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(AppRadii.small);
    final center = size.width / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = trackColor,
    );
    if (value != 0) {
      final end = center + value * center;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            value < 0 ? end : center,
            0,
            value < 0 ? center : end,
            size.height,
          ),
          radius,
        ),
        Paint()..color = color,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(center - _centerWidth / 2, 0, _centerWidth, size.height),
      Paint()..color = centerColor,
    );
  }

  @override
  bool shouldRepaint(_BalanceBarPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.centerColor != centerColor;
}
