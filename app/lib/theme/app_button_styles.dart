import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Button variants of section 8 of `docs/spec/stile.md` that a component
/// theme cannot tell apart: pass them as the `style` of the button.
///
/// ```dart
/// FilledButton(style: context.buttonStyles.compact, …)
/// FilledButton.tonal(style: context.buttonStyles.tonal, …)
/// OutlinedButton(style: context.buttonStyles.destructive, …)
/// ```
@immutable
class AppButtonStyles extends ThemeExtension<AppButtonStyles> {
  const new({
    required this.compact,
    required this.tonal,
    required this.destructive,
  });

  factory fromScheme(ColorScheme scheme) => AppButtonStyles(
    compact: const ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(AppSizes.minTouchTarget, AppSizes.compactButtonHeight),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    ),
    tonal: FilledButton.styleFrom(
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundColor: scheme.primary,
    ),
    destructive: OutlinedButton.styleFrom(foregroundColor: scheme.error),
  );

  /// Pill 44 high, for any button.
  final ButtonStyle compact;

  /// `surfaceContainerHighest` with `primary` text, for `FilledButton.tonal`.
  final ButtonStyle tonal;

  /// `error` text, for a destructive `OutlinedButton`.
  final ButtonStyle destructive;

  @override
  AppButtonStyles copyWith({
    ButtonStyle? compact,
    ButtonStyle? tonal,
    ButtonStyle? destructive,
  }) => AppButtonStyles(
    compact: compact ?? this.compact,
    tonal: tonal ?? this.tonal,
    destructive: destructive ?? this.destructive,
  );

  @override
  AppButtonStyles lerp(AppButtonStyles? other, double t) {
    if (other == null) return this;
    return AppButtonStyles(
      compact: ButtonStyle.lerp(compact, other.compact, t)!,
      tonal: ButtonStyle.lerp(tonal, other.tonal, t)!,
      destructive: ButtonStyle.lerp(destructive, other.destructive, t)!,
    );
  }
}

extension AppButtonStylesContext on BuildContext {
  /// The [AppButtonStyles] of the current theme.
  AppButtonStyles get buttonStyles =>
      Theme.of(this).extension<AppButtonStyles>()!;
}
