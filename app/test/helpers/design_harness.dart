import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'spec.dart';

/// Width of a phone, in dp: the width a component gets in the tests.
const phoneWidth = 360.0;

/// Font families that the golden tests draw with: the app font, the icons
/// and the icons Material uses inside its own components.
const Set<String> _goldenFontFamilies = {
  appFontFamily,
  'packages/material_symbols_icons/MaterialSymbolsRounded',
  'MaterialIcons',
};

/// Loads the real fonts of the app, as `FontManifest.json` lists them.
/// Without them the tests draw every letter as a rectangle.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (!_goldenFontFamilies.contains(family)) continue;
    final loader = FontLoader(family);
    final fonts = (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final font in fonts) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// [child] in the theme of one combination, as wide as a phone, with the
/// text at [textScale]. It scrolls, so tall components do not overflow.
Widget inTheme(
  (AppPalette, Brightness) combination,
  Widget child, {
  double textScale = 1,
}) {
  final (palette, brightness) = combination;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(palette, brightness),
    locale: const Locale('it'),
    supportedLocales: const [Locale('it')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: phoneWidth,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Unstretched(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps [child] with [inTheme] and waits for it to settle.
Future<void> pumpInTheme(
  WidgetTester tester,
  (AppPalette, Brightness) combination,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(inTheme(combination, child, textScale: textScale));
  await tester.pumpAndSettle();
}

/// Key of the area that a golden test compares.
const ValueKey<String> goldenKey = ValueKey('golden');

/// [builder] in the six combinations side by side, each as wide as a phone
/// and with the text at [textScale]: the picture of a golden test.
Widget sixCombinations(WidgetBuilder builder, {double textScale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('it'),
    supportedLocales: const [Locale('it')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: goldenKey,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (palette, brightness) in combinations)
              SizedBox(
                width: phoneWidth,
                child: Theme(
                  data: buildAppTheme(palette, brightness),
                  child: _GoldenCell(textScale: textScale, builder: builder),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The surface of one combination, as tall as the component.
class _GoldenCell extends StatelessWidget {
  const new({required this.textScale, required this.builder});

  final double textScale;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _Unstretched(child: Builder(builder: builder)),
        ),
      ),
    );
  }
}

/// Lets [child] choose its own size within the width of the phone, as the
/// component catalog does.
class _Unstretched extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topLeft, heightFactor: 1, child: child);
}
