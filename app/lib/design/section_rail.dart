import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/text_scale.dart';
import 'package:material_ui/material_ui.dart';

/// Side bar of a section, from the medium window class
/// (`docs/spec/navigazione.md`, section 5): the tabs of the bottom bar, with
/// their labels always visible, and room at the top for the "+" button.
///
/// The labels have the limit of the bottom bar, [AppTextScale.barLabelMax].
/// When the tabs do not fit the height of the window, they scroll.
class SectionRail extends StatelessWidget {
  const new({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.action,
    super.key,
  });

  final List<NavigationRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// The "+" button of the current tab. Without one its room stays empty,
  /// so the tabs do not move.
  final Widget? action;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: AppTextScale.barLabelMax,
    child: NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      scrollable: true,
      leading: SizedBox.square(dimension: AppSizes.fab, child: action),
      destinations: destinations,
    ),
  );
}
