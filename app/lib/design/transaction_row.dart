import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Row of a transaction in a list: icon, counterparty, a line of details
/// and the amount (section 8 of `docs/spec/stile.md`).
///
/// Every value arrives ready to show. The colour of the amount is the
/// neutral one until the Transactions specification defines the income
/// colour (section 2.2).
class TransactionRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.counterparty,
    required this.amount,
    this.details,
    this.onTap,
    super.key,
  });

  /// Icon of the category.
  final IconData icon;

  final String counterparty;

  /// Second line, such as category and account.
  final String? details;

  /// The amount, already formatted with its sign.
  final String amount;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = this.details;
    return ListTile(
      onTap: onTap,
      leading: SizedBox.square(
        dimension: AppSizes.listAvatar,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const CircleBorder(),
            color: scheme.surfaceContainerHighest,
          ),
          child: Icon(icon, color: scheme.onSurfaceVariant),
        ),
      ),
      title: Text(counterparty),
      titleTextStyle: theme.textTheme.titleMedium,
      subtitle: details == null ? null : Text(details),
      trailing: Text(
        amount,
        style: theme.textTheme.bodyLarge?.listAmount.copyWith(
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
