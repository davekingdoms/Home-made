import 'dart:math' as math;

import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Body of a screen with the phone layout: [children] in a column at most
/// [AppSizes.maxContentWidth] wide, centred on wide windows, with the side
/// margin of the screens. It scrolls when it does not fit, for example with
/// large text.
///
/// [centered] also centres the column vertically, for the screens with
/// little content such as sign-in.
class PhoneLayout extends StatelessWidget {
  const new({required this.children, this.centered = false, super.key});

  final List<Widget> children;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    const margin = AppSpacing.screenMargin;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(margin),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 2 * margin),
          ),
          child: Align(
            alignment: centered ? Alignment.center : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
