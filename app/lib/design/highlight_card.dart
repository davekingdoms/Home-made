import 'package:homemade/design/diagonal_band.dart';
import 'package:homemade/design/pressable.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Highlighted card: `primaryContainer` with the diagonal band (sections 2.2
/// and 8 of `docs/spec/stile.md`).
///
/// Inside [child] the texts and the text styles of the theme are white; use
/// `AppColors.suPrimarioTenue` for the subdued ones. Both stay readable over
/// the band.
class HighlightCard extends StatelessWidget {
  const new({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.radius = AppRadii.card,
    super.key,
  });

  final VoidCallback? onTap;

  /// Read by the screen reader in place of the texts of [child].
  final String? semanticLabel;

  final EdgeInsetsGeometry padding;

  /// 28, or 32 in the hub.
  final double radius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return Pressable(
      onTap: onTap,
      shape: shape,
      color: scheme.primaryContainer,
      semanticLabel: semanticLabel,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: DiagonalBand(color: context.appColors.banda),
            ),
          ),
          Padding(
            padding: padding,
            // Inside the card the text styles of the theme are white too.
            child: Theme(
              data: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  bodyColor: scheme.onPrimaryContainer,
                  displayColor: scheme.onPrimaryContainer,
                ),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: scheme.onPrimaryContainer),
                child: IconTheme.merge(
                  data: IconThemeData(color: scheme.onPrimaryContainer),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
