import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Surface of a hand-made component that can be tapped: Material 3 state
/// layers, a ring when focused, a touch target of at least 48 × 48 and
/// button semantics (sections 7 and 8 of `docs/spec/stile.md`).
///
/// Without [onTap] it is a plain surface, with no states; it still reads as
/// a button, a disabled one, only if [button] says so.
class Pressable extends StatefulWidget {
  const new({
    required this.child,
    this.onTap,
    this.button,
    this.shape = const StadiumBorder(),
    this.color = Colors.transparent,
    this.semanticLabel,
    super.key,
  });

  final VoidCallback? onTap;

  /// Whether the screen reader announces a button. By default, only when
  /// [onTap] is set.
  final bool? button;

  final OutlinedBorder shape;

  /// Fill of the surface.
  final Color color;

  /// Read by the screen reader in place of the texts of [child].
  final String? semanticLabel;

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onTap = widget.onTap;
    final label = widget.semanticLabel;
    final ring = BorderSide(
      color: scheme.secondary,
      width: AppSizes.focusRing,
      strokeAlign: BorderSide.strokeAlignOutside,
    );

    final surface = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
      // Not clipped, so that the focus ring shows outside the shape.
      child: Material(
        color: widget.color,
        shape: _focused ? widget.shape.copyWith(side: ring) : widget.shape,
        child: InkWell(
          onTap: onTap,
          customBorder: widget.shape,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: widget.child,
        ),
      ),
    );

    if (!(widget.button ?? onTap != null)) {
      return label == null
          ? surface
          : Semantics(label: label, excludeSemantics: true, child: surface);
    }
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: label != null,
      onTap: label == null ? null : onTap,
      child: surface,
    );
  }
}
