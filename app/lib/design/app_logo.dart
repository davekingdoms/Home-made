import 'package:homemade/design/cookie.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Stand-in for the logo of the app until the real one arrives: a house on
/// a cookie, in the primary colours. Like the placeholder, it is not a
/// component of the style specification.
class AppLogo extends StatelessWidget {
  const new({this.size = defaultSize, this.semanticLabel, super.key});

  /// Twice the avatar of the hub.
  static const double defaultSize = AppSizes.hubAvatar * 2;

  final double size;

  /// What the screen reader says; null when the name of the app is already
  /// written next to the logo.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.primary,
            shape: const CookieBorder(),
          ),
          child: Icon(
            Symbols.home_rounded,
            size: size / 2,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
