import 'package:homemade/theme/motion.dart';
import 'package:material_ui/material_ui.dart';

/// Page transitions of the app on Android (section 6 of
/// `docs/spec/stile.md`): horizontal "shared axis" when a screen opens or
/// closes, and the stock predictive back while the back gesture is dragged.
///
/// The predictive back of Material stays in charge of the gesture: this
/// builder only replaces the transition it falls back to outside a gesture.
class AppPageTransitionsBuilder extends PredictiveBackPageTransitionsBuilder {
  const new();

  @override
  Duration get transitionDuration => AppDurations.long;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // During the gesture the predictive back animates the routes and the
    // shared axis stands still; otherwise it is the other way round. The
    // widgets stay the same in both cases, so the screen keeps its state.
    final gesture = route.popGestureInProgress;
    return super.buildTransitions(
      route,
      context,
      gesture ? animation : kAlwaysCompleteAnimation,
      gesture ? secondaryAnimation : kAlwaysDismissedAnimation,
      SharedAxisTransition(
        animation: gesture ? kAlwaysCompleteAnimation : animation,
        secondaryAnimation: gesture
            ? kAlwaysDismissedAnimation
            : secondaryAnimation,
        opaque: route.opaque,
        child: child,
      ),
    );
  }
}

/// Horizontal "shared axis" transition of Material 3, written with Flutter
/// primitives.
///
/// [animation] brings [child] in from the end side while it fades in;
/// [secondaryAnimation] moves it out towards the start side while it fades
/// out, when another screen covers it. Running backwards, they undo the same
/// movements. With "reduce animations" both are short fades.
class SharedAxisTransition extends StatelessWidget {
  const new({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    this.opaque = true,
    super.key,
  });

  /// Distance travelled along the axis, in dp.
  static const double distance = 30;

  /// Fraction of the duration in which the outgoing screen fades out, before
  /// the incoming one fades in.
  static const double fadeOutEnd = 0.3;

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;

  /// Whether [child] covers what is under it: its place is then filled with
  /// the surface colour while it fades out.
  final bool opaque;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final fillColor = opaque
        ? Theme.of(context).colorScheme.surface
        : Colors.transparent;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final frame = _frame(animation, reduceMotion: reduceMotion);
        return Opacity(
          opacity: frame.opacity,
          child: Transform.translate(
            offset: Offset(direction * distance * frame.shift, 0),
            child: child,
          ),
        );
      },
      child: ColoredBox(
        color: fillColor,
        child: AnimatedBuilder(
          animation: secondaryAnimation,
          builder: (context, child) {
            // Seen from the screen underneath, the other one leaving is this
            // one entering: the same frames, mirrored.
            final frame = _frame(
              ReverseAnimation(secondaryAnimation),
              reduceMotion: reduceMotion,
            );
            return Opacity(
              opacity: frame.opacity,
              child: Transform.translate(
                offset: Offset(-direction * distance * frame.shift, 0),
                child: child,
              ),
            );
          },
          child: child,
        ),
      ),
    );
  }

  /// Opacity and shift (as a fraction of [distance]) of a screen whose
  /// [animation] goes from 0, out of the screen, to 1, in its place.
  static ({double opacity, double shift}) _frame(
    Animation<double> animation, {
    required bool reduceMotion,
  }) {
    final value = animation.value;
    final leaving = animation.status == AnimationStatus.reverse;
    if (leaving) {
      final progress = 1 - value;
      return (
        opacity: TransitionTimeline.fadeOut(
          progress,
          end: fadeOutEnd,
          reduceMotion: reduceMotion,
        ),
        shift: reduceMotion ? 0 : AppCurves.exit.transform(progress),
      );
    }
    return (
      opacity: TransitionTimeline.fadeIn(
        value,
        start: fadeOutEnd,
        reduceMotion: reduceMotion,
      ),
      shift: reduceMotion ? 0 : 1 - AppCurves.enter.transform(value),
    );
  }
}
