import 'package:homemade/design/cookie.dart';
import 'package:homemade/design/pressable.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Quick tile with a number on a cookie and what it counts (section 8 of
/// `docs/spec/stile.md`): for example 8 transactions to classify.
class CookieTile extends StatelessWidget {
  const new({
    required this.count,
    required this.label,
    required this.semanticLabel,
    this.onTap,
    super.key,
  });

  final int count;

  /// Short text beside the cookie, such as "da classificare".
  final String label;

  /// The whole sentence for the screen reader, such as
  /// "8 transazioni da classificare".
  final String semanticLabel;

  final VoidCallback? onTap;

  /// Fits a pill 48 high.
  static const double _cookieSize = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _QuickTile(
      onTap: onTap,
      semanticLabel: semanticLabel,
      children: [
        CookieCounter(
          count: count,
          semanticLabel: semanticLabel,
          size: _cookieSize,
        ),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Quick tile with a caption and a value in a pill (section 8): for example
/// a balance, already formatted.
class PillTile extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;

  /// The value, ready to show.
  final String value;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _QuickTile(
      onTap: onTap,
      semanticLabel: '$label: $value',
      children: [
        Flexible(
          child: Text(
            label,
            // Never the tertiary text over this surface (section 2.2).
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.labelLarge?.amount.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pill over `surfaceContainerHighest`, at least 48 high.
class _QuickTile extends StatelessWidget {
  const new({
    required this.children,
    required this.semanticLabel,
    required this.onTap,
  });

  final List<Widget> children;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      semanticLabel: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs,
          children: children,
        ),
      ),
    );
  }
}
