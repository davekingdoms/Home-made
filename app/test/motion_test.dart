import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/fade_through_stack.dart';
import 'package:homemade/theme/motion.dart';
import 'package:homemade/theme/page_transitions.dart';
import 'package:material_ui/material_ui.dart';

/// The opacity and the horizontal shift that a transition gives to [child].
({double opacity, double dx}) _frameOf(WidgetTester tester, Finder child) {
  final opacity = tester.widget<Opacity>(
    find.ancestor(of: child, matching: find.byType(Opacity)).first,
  );
  final transform = tester.widget<Transform>(
    find.ancestor(of: child, matching: find.byType(Transform)).first,
  );
  return (
    opacity: opacity.opacity,
    dx: transform.transform.getTranslation().x,
  );
}

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child,
    ),
  ),
);

void main() {
  test('durations and curves are those of section 6', () {
    expect(AppDurations.short, const Duration(milliseconds: 150));
    expect(AppDurations.medium, const Duration(milliseconds: 300));
    expect(AppDurations.long, const Duration(milliseconds: 500));
    expect(AppCurves.enter, Easing.emphasizedDecelerate);
    expect(AppCurves.exit, Easing.emphasizedAccelerate);
    expect(
      const AppPageTransitionsBuilder().transitionDuration,
      AppDurations.long,
    );
  });

  group('fade through', () {
    Widget stack(int index) => FadeThroughStack(
      currentIndex: index,
      children: const [Text('first'), Text('second')],
    );

    testWidgets('shows the current child and keeps the others hidden', (
      tester,
    ) async {
      await tester.pumpWidget(_app(stack(0)));

      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);
      expect(find.text('second', skipOffstage: false), findsOneWidget);
    });

    testWidgets('the old child fades out, then the new one fades in', (
      tester,
    ) async {
      await tester.pumpWidget(_app(stack(0)));
      await tester.pumpWidget(_app(stack(1)));

      // At 20% the old child is going and the new one is not there yet.
      await tester.pump(AppDurations.long * 0.2);
      final leaving = _frameOf(tester, find.text('first'));
      expect(leaving.opacity, inExclusiveRange(0, 1));
      expect(_frameOf(tester, find.text('second')).opacity, 0);

      // At 70% only the new one shows, still growing.
      await tester.pump(AppDurations.long * 0.5);
      expect(find.text('first'), findsOneWidget);
      expect(_frameOf(tester, find.text('first')).opacity, 0);
      final entering = _frameOf(tester, find.text('second'));
      expect(entering.opacity, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(find.text('first'), findsNothing);
      expect(_frameOf(tester, find.text('second')).opacity, 1);
    });

    testWidgets('with "reduce animations" it is a short fade', (tester) async {
      await tester.pumpWidget(_app(stack(0), reduceMotion: true));
      await tester.pumpWidget(_app(stack(1), reduceMotion: true));

      // Done after 150 ms, well before the 500 of the full transition.
      await tester.pump(AppDurations.short);
      expect(_frameOf(tester, find.text('first')).opacity, 0);
      expect(_frameOf(tester, find.text('second')).opacity, 1);
      final scale = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('second'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), 1);
    });
  });

  group('shared axis', () {
    late AnimationController primary;
    late AnimationController secondary;

    Widget transition({bool reduceMotion = false}) => _app(
      SharedAxisTransition(
        animation: primary,
        secondaryAnimation: secondary,
        child: const Text('screen'),
      ),
      reduceMotion: reduceMotion,
    );

    setUp(() {
      primary = AnimationController(
        vsync: const TestVSync(),
        duration: AppDurations.long,
      );
      secondary = AnimationController(
        vsync: const TestVSync(),
        duration: AppDurations.long,
      );
    });

    tearDown(() {
      primary.dispose();
      secondary.dispose();
    });

    /// Opacities around the screen: first the one of the covering
    /// transition, then the one of its own entrance.
    List<double> opacities(WidgetTester tester) => [
      for (final opacity in tester.widgetList<Opacity>(
        find.ancestor(of: find.text('screen'), matching: find.byType(Opacity)),
      ))
        opacity.opacity,
    ];

    /// Horizontal shifts around the screen, in the same order.
    List<double> shifts(WidgetTester tester) => [
      for (final transform in tester.widgetList<Transform>(
        find.ancestor(
          of: find.text('screen'),
          matching: find.byType(Transform),
        ),
      ))
        transform.transform.getTranslation().x,
    ];

    testWidgets('a screen enters from the end side while it fades in', (
      tester,
    ) async {
      await tester.pumpWidget(transition());
      expect(opacities(tester)[1], 0);

      primary.value = 0.6;
      await tester.pump();
      expect(opacities(tester)[1], inExclusiveRange(0, 1));
      expect(
        shifts(tester)[1],
        inExclusiveRange(0, SharedAxisTransition.distance),
      );
      // Nothing covers it: that transition stands still.
      expect(opacities(tester)[0], 1);
      expect(shifts(tester)[0], 0);

      primary.value = 1;
      await tester.pump();
      expect(opacities(tester).take(2), [1, 1]);
      expect(shifts(tester).take(2), [0, 0]);
    });

    testWidgets('a covered screen leaves towards the start side', (
      tester,
    ) async {
      primary.value = 1;
      await tester.pumpWidget(transition());

      // Another screen starts covering this one.
      secondary.value = 0.1;
      await tester.pump();
      expect(opacities(tester)[0], inExclusiveRange(0, 1));
      expect(shifts(tester)[0], lessThan(0));
      expect(opacities(tester)[1], 1);
    });

    testWidgets('with "reduce animations" nothing moves', (tester) async {
      await tester.pumpWidget(transition(reduceMotion: true));

      primary.value = 0.2;
      await tester.pump();
      expect(shifts(tester).take(2), [0, 0]);

      // The fade is over after 150 ms of the 500.
      primary.value = 0.3;
      await tester.pump();
      expect(opacities(tester)[1], 1);
    });
  });
}
