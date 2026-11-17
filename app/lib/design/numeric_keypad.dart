import 'package:homemade/design/pressable.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Numeric keypad with pill keys, for typing an amount (section 8 of
/// `docs/spec/stile.md`).
///
/// It holds no amount: it only reports the keys. Without a callback its key
/// is disabled.
class NumericKeypad extends StatelessWidget {
  const new({
    required this.onDigit,
    required this.onDecimalSeparator,
    required this.onBackspace,
    super.key,
  });

  /// A digit from 0 to 9 was pressed.
  final ValueChanged<int>? onDigit;

  /// The comma was pressed.
  final VoidCallback? onDecimalSeparator;

  final VoidCallback? onBackspace;

  /// Height of a key.
  static const double keyHeight = 56;

  @override
  Widget build(BuildContext context) {
    final onDigit = this.onDigit;
    Widget digit(int value) => _KeypadKey(
      semanticLabel: '$value',
      onTap: onDigit == null ? null : () => onDigit(value),
      child: Text('$value'),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          _KeypadRow(children: [for (final value in row) digit(value)]),
        _KeypadRow(
          children: [
            _KeypadKey(
              semanticLabel: 'Virgola',
              onTap: onDecimalSeparator,
              child: const Text(','),
            ),
            digit(0),
            _KeypadKey(
              semanticLabel: 'Cancella',
              onTap: onBackspace,
              child: const Icon(Symbols.backspace_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadRow extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: AppSpacing.xs,
      children: [for (final child in children) Expanded(child: child)],
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const new({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final foreground = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: AppOpacities.disabledContent);
    final background = enabled
        ? scheme.surfaceContainerHighest
        : scheme.onSurface.withValues(alpha: AppOpacities.disabledContainer);
    return Pressable(
      onTap: onTap,
      button: true,
      semanticLabel: semanticLabel,
      color: background,
      child: SizedBox(
        height: NumericKeypad.keyHeight,
        child: Center(
          // The keys keep their height: large text shrinks to fit.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: IconTheme.merge(
              data: IconThemeData(color: foreground),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.headlineSmall?.amount.copyWith(
                  color: foreground,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
