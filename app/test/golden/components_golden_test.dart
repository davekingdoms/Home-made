@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/dev/component_catalog.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/design_harness.dart';
import '../helpers/spec.dart';

/// Room for the six combinations side by side, each as wide as a phone, and
/// for the tallest component with the text at 200%.
const _surface = Size(phoneWidth * 6, 2400);

/// One picture per component of section 8 of `docs/spec/stile.md`, with the
/// six combinations side by side, plus one with the text at 200% for the
/// components that have text. They are the catalog of the specification.
///
/// The reference pictures are drawn on Linux, by the CI: to regenerate them,
/// add the `update-goldens` label to the pull request or run the "Update
/// goldens" workflow on the branch (see CLAUDE.md, section CI).
void main() {
  setUpAll(loadAppFonts);

  test('the pictures show the six combinations of section 2.1', () {
    expect(combinations, hasLength(6));
    expect(_surface.width, phoneWidth * combinations.length);
  });

  for (final entry in componentCatalog) {
    testWidgets('${entry.id} in the six combinations', (tester) async {
      await _pumpGolden(tester, entry.builder);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/${entry.id}.png'),
      );
    });

    if (entry.hasText) {
      testWidgets('${entry.id} with the text at 200%', (tester) async {
        await _pumpGolden(tester, entry.builder, textScale: 2);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/${entry.id}_text_200.png'),
        );
      });
    }
  }
}

Future<void> _pumpGolden(
  WidgetTester tester,
  WidgetBuilder builder, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  // The tests draw shadows as solid black outlines; the catalog shows the
  // real ones, as the phone draws them.
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);

  await tester.pumpWidget(sixCombinations(builder, textScale: textScale));
  await tester.pumpAndSettle();
}
