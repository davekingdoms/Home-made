import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Material 3 width class of the window (`docs/spec/navigazione.md`,
/// section 5): the one place that computes it.
///
/// It comes from the width of the window, never from the device or the
/// display: a tablet in split screen or in a floating window can be compact.
enum WindowClass {
  /// Below 600 dp: the phone layout.
  compact,

  /// From 600 to 839 dp.
  medium,

  /// From 840 dp.
  expanded;

  /// The class of a window [width] dp wide.
  static WindowClass fromWidth(double width) {
    if (width < AppBreakpoints.medium) return compact;
    if (width < AppBreakpoints.expanded) return medium;
    return expanded;
  }

  /// The class of the window of [context]; the widget that asks rebuilds
  /// when the window changes size.
  static WindowClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  /// Whether the sections use the side bar instead of the bottom bar.
  bool get hasSideBar => this != compact;
}
