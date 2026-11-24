import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// The centred column of the screens (`docs/spec/navigazione.md`, section
/// 5): [child] at most [AppSizes.maxContentWidth] wide, centred on wide
/// windows, as wide as the room on a phone.
///
/// Inside a scrollable it takes the height of [child]; place it inside the
/// scrollable, not around it, so that the whole window still scrolls.
class ContentColumn extends StatelessWidget {
  const new({
    required this.child,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;

  /// Where the column goes when it has room on both axes.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
      child: child,
    ),
  );
}
