import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Label of a chip that opens a choice, such as the period or the accounts:
/// the text followed by a small arrow (section 8 of `docs/spec/stile.md`).
class ChipArrowLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xxs,
      children: [
        Flexible(child: Text(text)),
        const Icon(
          Symbols.keyboard_arrow_down_rounded,
          size: AppSizes.iconHouse,
        ),
      ],
    );
  }
}
