import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Row to choose a palette: three dots with its colours, its name and a
/// radio (section 8 of `docs/spec/stile.md`).
///
/// It goes under a `RadioGroup<AppPalette>`, which holds the choice.
class PaletteRadioTile extends StatelessWidget {
  const new({required this.palette, super.key});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = tokensOf(palette, theme.brightness);
    return RadioListTile<AppPalette>(
      value: palette,
      title: Text(palette.label),
      secondary: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xxs,
          children: [
            for (final color in [
              tokens.primaryContainer,
              tokens.primary,
              tokens.secondaryContainer,
            ])
              SizedBox.square(
                dimension: AppSpacing.md,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color,
                    shape: CircleBorder(
                      side: BorderSide(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      controlAffinity: ListTileControlAffinity.trailing,
      tileColor: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.choiceRow),
      ),
    );
  }
}
