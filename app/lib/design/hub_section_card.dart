import 'package:homemade/design/pressable.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// One of the two quick facts of a [HubSectionCard]: a value with a short
/// caption, both ready to show.
@immutable
class HubQuickFact {
  const new({required this.value, required this.label});

  final String value;
  final String label;
}

/// Card of a section in the hub: round icon, name, state and up to two
/// quick facts (section 8 of `docs/spec/stile.md`).
///
/// With [onTap] the section is active; without, it is "In arrivo" and cannot
/// be opened.
class HubSectionCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.name,
    this.status,
    this.facts = const [],
    this.onTap,
    super.key,
  });

  /// Text shown in place of the state of a section that is not built yet.
  static const comingSoonLabel = 'In arrivo';

  final IconData icon;
  final String name;

  /// State of an active section, such as "Tutto in ordine".
  final String? status;

  /// Only the first two are shown.
  final List<HubQuickFact> facts;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final active = onTap != null;
    final status = active ? this.status : comingSoonLabel;

    final card = Pressable(
      onTap: onTap,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.hubCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.hubGridCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              spacing: AppSpacing.sm,
              children: [
                // The subdued accent is a fill only (section 2.2).
                SizedBox.square(
                  dimension: AppSizes.hubAvatar,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: const CircleBorder(),
                      color: active
                          ? scheme.tertiary
                          : scheme.surfaceContainerHigh,
                    ),
                    child: Icon(
                      icon,
                      color: active
                          ? scheme.onTertiary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.titleMedium?.copyWith(
                          color: active
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status,
                          style: textTheme.bodySmall?.copyWith(
                            color: active
                                ? scheme.onSurfaceVariant
                                : context.appColors.testoTerziario,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (active && facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.sm,
                children: [
                  for (final fact in facts.take(2))
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fact.value,
                            style: textTheme.titleSmall?.amount,
                          ),
                          Text(
                            fact.label,
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    // A section that cannot be opened is read as one sentence.
    return active ? card : MergeSemantics(child: card);
  }
}
