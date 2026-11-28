import 'package:homemade/features/household/cash_amount.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Label of the field of the cash, in A8 and A10.
const cashLabel = 'Quanti contanti hai adesso?';

/// A start date (A8, A10): an outlined field that cannot be written, with
/// the calendar at the end; a tap opens the date picker. Under it, the
/// [helper], as Material places the helper of a field. The screen reader
/// hears it as one button called [semanticLabel].
class StartDateField extends StatelessWidget {
  const new({
    required this.label,
    required this.text,
    required this.semanticLabel,
    required this.helper,
    required this.onTap,
    super.key,
  });

  final String label;

  /// The date, as the field shows it.
  final String text;

  final String semanticLabel;
  final String helper;

  /// Null while the field cannot change: it looks disabled.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          enabled: enabled,
          label: semanticLabel,
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.textField),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                enabled: enabled,
                suffixIcon: const Icon(Symbols.calendar_month_rounded),
              ),
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(
                          alpha: AppOpacities.disabledContent,
                        ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          // Where Material puts the helper of an outlined field: the padding
          // of the content plus the gap of the border (4).
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.md + AppSpacing.xxs,
            end: AppSpacing.md + AppSpacing.xxs,
            top: AppSpacing.xxs,
          ),
          child: Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Quanti contanti hai adesso?" (A8, A10; `docs/spec/accesso.md`, section
/// 6): outlined, with "€" at the end, the placeholder "0,00", tabular
/// figures and the numeric keyboard with the decimal; [CashAmountFormatter]
/// filters what is written.
class CashField extends StatelessWidget {
  const new({
    required this.controller,
    required this.enabled,
    required this.helper,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountStyle = theme.textTheme.bodyLarge?.amount;
    return TextField(
      controller: controller,
      enabled: enabled,
      style: amountStyle,
      decoration: InputDecoration(
        labelText: cashLabel,
        // The label stays up, so that the placeholder and the euro show from
        // the start.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: '0,00',
        hintStyle: amountStyle?.copyWith(
          color: context.appColors.testoTerziario,
        ),
        suffixText: '€',
        suffixStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        helperText: helper,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      inputFormatters: const [CashAmountFormatter()],
    );
  }
}
