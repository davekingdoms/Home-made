import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Kind of a [NoticeCard]. Each has its own icon and its own name for the
/// screen reader: the colour is never the only signal.
enum NoticeKind {
  error('Errore', Symbols.error_rounded),
  warning('Avviso', Symbols.warning_rounded),
  info('Informazione', Symbols.info_rounded);

  new(this.label, this.icon);

  /// Italian name, read before the title.
  final String label;

  final IconData icon;
}

/// Notice: coloured icon, title, subtitle and an optional pill action over
/// `surfaceContainerHigh` (section 8 of `docs/spec/stile.md`).
class NoticeCard extends StatelessWidget {
  const new({
    required this.kind,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'The action needs both its label and its callback',
       );

  final NoticeKind kind;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = this.subtitle;
    final actionLabel = this.actionLabel;
    final iconColor = switch (kind) {
      NoticeKind.error => scheme.error,
      NoticeKind.warning => context.appColors.avviso,
      NoticeKind.info => scheme.primary,
    };
    // With large text the action goes under the texts instead of beside.
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > AppTextScale.hubMax;

    // One node for the screen reader: kind, title and subtitle.
    final texts = Semantics(
      container: true,
      label: kind.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
    final action = actionLabel == null
        ? null
        : FilledButton.tonal(
            style: context.buttonStyles.tonal.merge(
              context.buttonStyles.compact,
            ),
            onPressed: onAction,
            child: Text(actionLabel),
          );

    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.sm,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Icon(kind.icon, color: iconColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.sm,
                children: [texts, if (action != null && stacked) action],
              ),
            ),
            if (action != null && !stacked) action,
          ],
        ),
      ),
    );
  }
}
