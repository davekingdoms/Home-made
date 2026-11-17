import 'package:homemade/theme/motion.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps all its [children] alive and shows the one at [currentIndex]; when
/// the index changes, the old child fades out and then the new one fades in
/// while it grows slightly: the "fade through" of Material 3, written with
/// Flutter primitives (section 6 of `docs/spec/stile.md`).
///
/// With "reduce animations" the two fades are short and nothing grows.
class FadeThroughStack extends StatefulWidget {
  const new({required this.currentIndex, required this.children, super.key});

  final int currentIndex;
  final List<Widget> children;

  /// Fraction of the duration in which the old child fades out, before the
  /// new one fades in.
  static const double fadeOutEnd = 0.35;

  /// Scale the new child starts from.
  static const double startScale = 0.92;

  @override
  State<FadeThroughStack> createState() => _FadeThroughStackState();
}

class _FadeThroughStackState extends State<FadeThroughStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.long,
    value: 1,
  );

  /// The child that is fading out, while the transition runs.
  int? _previousIndex;

  @override
  void didUpdateWidget(FadeThroughStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _controller.value;
        final running = progress < 1;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final (index, child) in widget.children.indexed)
              _layer(
                child,
                current: index == widget.currentIndex,
                leaving: running && index == _previousIndex,
                progress: progress,
                reduceMotion: reduceMotion,
              ),
          ],
        );
      },
    );
  }

  /// One child with its opacity and scale. The widgets around it are always
  /// the same, so it keeps its state when it is hidden.
  Widget _layer(
    Widget child, {
    required bool current,
    required bool leaving,
    required double progress,
    required bool reduceMotion,
  }) {
    var opacity = 0.0;
    var scale = 1.0;
    if (current) {
      opacity = TransitionTimeline.fadeIn(
        progress,
        start: FadeThroughStack.fadeOutEnd,
        reduceMotion: reduceMotion,
      );
      if (!reduceMotion) {
        final grown = const Interval(
          FadeThroughStack.fadeOutEnd,
          1,
          curve: AppCurves.enter,
        ).transform(progress);
        scale =
            FadeThroughStack.startScale +
            (1 - FadeThroughStack.startScale) * grown;
      }
    } else if (leaving) {
      opacity = TransitionTimeline.fadeOut(
        progress,
        end: FadeThroughStack.fadeOutEnd,
        reduceMotion: reduceMotion,
      );
    }

    return Offstage(
      offstage: !current && !leaving,
      child: TickerMode(
        enabled: current,
        child: IgnorePointer(
          ignoring: !current,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      ),
    );
  }
}
