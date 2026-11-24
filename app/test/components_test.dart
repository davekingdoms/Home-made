import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/design/balance_bar.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/design/hub_section_card.dart';
import 'package:homemade/design/notice_card.dart';
import 'package:homemade/design/number_tile.dart';
import 'package:homemade/design/numeric_keypad.dart';
import 'package:homemade/design/palette_radio_tile.dart';
import 'package:homemade/design/quick_tiles.dart';
import 'package:homemade/design/transaction_row.dart';
import 'package:homemade/features/dev/component_catalog.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/design_harness.dart';
import 'helpers/spec.dart';

const (AppPalette, Brightness) _tealDark = (AppPalette.teal, Brightness.dark);
const (AppPalette, Brightness) _tealLight = (AppPalette.teal, Brightness.light);

/// Matches a size with both sides of at least 48: the minimum touch target.
final Matcher _isTouchTarget = predicate<Size>(
  (size) =>
      size.width >= AppSizes.minTouchTarget &&
      size.height >= AppSizes.minTouchTarget,
  'at least 48 × 48',
);

void main() {
  setUpAll(loadAppFonts);

  group('catalog', () {
    test('has every component of section 8, once', () {
      final ids = componentCatalog.map((entry) => entry.id).toSet();
      final titles = componentCatalog.map((entry) => entry.title).toSet();
      expect(ids, hasLength(componentCatalog.length));
      expect(titles, hasLength(componentCatalog.length));
      // The table has 26 rows; the hub house waits for its specification.
      expect(componentCatalog, hasLength(25));
    });

    for (final entry in componentCatalog) {
      for (final combination in combinations) {
        testWidgets(
          '${entry.id} builds in ${describeCombination(combination)}',
          (tester) async {
            await pumpInTheme(
              tester,
              combination,
              Builder(builder: entry.builder),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }

      if (entry.hasText) {
        testWidgets('${entry.id} fits with the text at 200%', (tester) async {
          await pumpInTheme(
            tester,
            _tealDark,
            Builder(builder: entry.builder),
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the side bar shows its tabs whole, also at 200%', (
      tester,
    ) async {
      final rail = componentCatalog.singleWhere(
        (entry) => entry.id == 'navigation_rail',
      );
      for (final textScale in [1.0, 2.0]) {
        await pumpInTheme(
          tester,
          _tealDark,
          Builder(builder: rail.builder),
          textScale: textScale,
        );
        final tabs = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byType(Scrollable),
          ),
        );
        expect(tabs.position.maxScrollExtent, 0, reason: '$textScale');
      }
    });
  });

  group('cookie', () {
    test('the border has twelve lobes', () {
      const size = 100.0;
      final path = const CookieBorder().getOuterPath(
        Offset.zero & const Size.square(size),
      );
      const center = Offset(size / 2, size / 2);
      // Between the bottom of a hollow and the tip of a lobe.
      const radius = size / 2 * (1 - CookieBorder.depth / 2);
      Offset at(double turns) {
        final angle = 2 * math.pi * turns;
        return center + Offset(math.sin(angle), -math.cos(angle)) * radius;
      }

      expect(CookieBorder.lobes, 12);
      expect(path.contains(center), isTrue);
      for (var lobe = 0; lobe < CookieBorder.lobes; lobe++) {
        expect(path.contains(at(lobe / 12)), isTrue, reason: 'lobe $lobe');
        expect(
          path.contains(at((lobe + 0.5) / 12)),
          isFalse,
          reason: 'hollow after lobe $lobe',
        );
      }
    });

    testWidgets('the avatar shows the initial and reads the name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpInTheme(
        tester,
        _tealDark,
        const CookieAvatar(name: 'anna', size: AppSizes.hubAvatar),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.bySemanticsLabel('anna'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CookieAvatar)),
        const Size.square(AppSizes.hubAvatar),
      );
      // Subdued accent as a fill, with its own text colour (section 2.2).
      final text = tester.widget<Text>(find.text('A'));
      expect(text.style?.color, tealDark.onTertiary);
      semantics.dispose();
    });

    testWidgets('the counter reads what it counts', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpInTheme(
        tester,
        _tealLight,
        const CookieCounter(
          count: 8,
          semanticLabel: '8 transazioni da classificare',
        ),
      );

      expect(find.text('8'), findsOneWidget);
      expect(
        find.bySemanticsLabel('8 transazioni da classificare'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('highlighted card', () {
    testWidgets('is primaryContainer with white text and can be tapped', (
      tester,
    ) async {
      var taps = 0;
      await pumpInTheme(
        tester,
        _tealLight,
        HighlightCard(
          onTap: () => taps++,
          child: Builder(
            builder: (context) => Text(
              'Saldo della casa',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(HighlightCard),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, tealLight.primaryContainer);
      final text = tester.widget<Text>(find.text('Saldo della casa'));
      expect(text.style?.color, tealLight.onPrimaryContainer);
      expect(tester.getSize(find.byType(HighlightCard)), _isTouchTarget);

      await tester.tap(find.byType(HighlightCard));
      expect(taps, 1);
    });
  });

  group('notice', () {
    for (final kind in NoticeKind.values) {
      testWidgets('${kind.name} has its icon, its name and its colour', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        var actions = 0;
        await pumpInTheme(
          tester,
          _tealLight,
          NoticeCard(
            kind: kind,
            title: 'Titolo di prova',
            subtitle: 'Sottotitolo di prova',
            actionLabel: 'Apri',
            onAction: () => actions++,
          ),
        );

        final icon = tester.widget<Icon>(find.byIcon(kind.icon));
        final colors = Theme.of(tester.element(find.byType(NoticeCard)))
            .extension<AppColors>()!;
        expect(icon.color, switch (kind) {
          NoticeKind.error => tealLight.error,
          NoticeKind.warning => colors.avviso,
          NoticeKind.info => tealLight.primary,
        });
        // The kind is said in words too, not by the colour alone.
        expect(
          find.bySemanticsLabel(RegExp('^${kind.label}\\s+Titolo di prova')),
          findsOneWidget,
        );
        expect(
          tester.widget<Card>(find.byType(Card)).color,
          tealLight.surfaceContainerHigh,
        );

        expect(tester.getSize(find.byType(FilledButton)), _isTouchTarget);
        await tester.tap(find.text('Apri'));
        expect(actions, 1);
        semantics.dispose();
      });
    }

    testWidgets('without an action it has no button', (tester) async {
      await pumpInTheme(
        tester,
        _tealDark,
        const NoticeCard(kind: NoticeKind.info, title: 'Titolo di prova'),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('hub section card', () {
    testWidgets('an active section shows state and facts and opens', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await pumpInTheme(
        tester,
        _tealDark,
        HubSectionCard(
          icon: Symbols.account_balance_wallet_rounded,
          name: 'Finanze',
          status: 'Tutto in ordine',
          facts: const [
            HubQuickFact(value: '12', label: 'Movimenti'),
            HubQuickFact(value: '3', label: 'Conti'),
            HubQuickFact(value: '9', label: 'Di troppo'),
          ],
          onTap: () => taps++,
        ),
      );

      expect(find.text('Tutto in ordine'), findsOneWidget);
      expect(find.text('Movimenti'), findsOneWidget);
      expect(find.text('Conti'), findsOneWidget);
      // Two quick facts at most.
      expect(find.text('Di troppo'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Finanze')), findsOneWidget);
      expect(tester.getSize(find.byType(HubSectionCard)), _isTouchTarget);

      await tester.tap(find.text('Finanze'));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('a section that is not built yet is "In arrivo"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpInTheme(
        tester,
        _tealDark,
        const HubSectionCard(
          icon: Symbols.kitchen_rounded,
          name: 'Dispensa',
          status: 'Ignorato',
          facts: [HubQuickFact(value: '1', label: 'Ignorato anche questo')],
        ),
      );

      expect(find.text(HubSectionCard.comingSoonLabel), findsOneWidget);
      expect(find.text('Ignorato'), findsNothing);
      expect(find.text('Ignorato anche questo'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'Dispensa\s+In arrivo')),
        findsOneWidget,
      );
      final colors = Theme.of(tester.element(find.byType(HubSectionCard)))
          .extension<AppColors>()!;
      final status = tester.widget<Text>(
        find.text(HubSectionCard.comingSoonLabel),
      );
      expect(status.style?.color, colors.testoTerziario);
      semantics.dispose();
    });
  });

  group('quick tiles', () {
    testWidgets('the cookie tile reads its whole sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await pumpInTheme(
        tester,
        _tealDark,
        CookieTile(
          count: 8,
          label: 'da classificare',
          semanticLabel: '8 transazioni da classificare',
          onTap: () => taps++,
        ),
      );

      expect(find.text('8'), findsOneWidget);
      expect(find.text('da classificare'), findsOneWidget);
      expect(
        find.bySemanticsLabel('8 transazioni da classificare'),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(CookieTile)), _isTouchTarget);

      await tester.tap(find.byType(CookieTile));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('the pill tile reads caption and value', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await pumpInTheme(
        tester,
        _tealDark,
        PillTile(label: 'Contanti', value: '35,00', onTap: () => taps++),
      );

      expect(find.bySemanticsLabel('Contanti: 35,00'), findsOneWidget);
      expect(tester.getSize(find.byType(PillTile)), _isTouchTarget);

      await tester.tap(find.byType(PillTile));
      expect(taps, 1);
      semantics.dispose();
    });
  });

  testWidgets('number tile: caption and amount, read together', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpInTheme(
      tester,
      _tealDark,
      const NumberTile(label: 'Entrate', amount: '2.450,00'),
    );

    expect(find.text('Entrate'), findsOneWidget);
    expect(find.text('2.450,00'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Entrate\s+2\.450,00')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('transaction row: a list row with a tabular amount', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpInTheme(
      tester,
      _tealDark,
      Material(
        child: TransactionRow(
          icon: Symbols.shopping_cart_rounded,
          counterparty: 'Mercato del Borgo',
          details: 'Spesa',
          amount: '45,20',
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.text('Mercato del Borgo'), findsOneWidget);
    expect(find.text('Spesa'), findsOneWidget);
    final amount = tester.widget<Text>(find.text('45,20'));
    expect(amount.style?.fontFeatures, const [FontFeature.tabularFigures()]);
    expect(amount.style?.fontWeight, FontWeight.w600);
    expect(
      tester.getSize(find.byType(TransactionRow)).height,
      greaterThanOrEqualTo(AppSizes.listRowMinHeight),
    );
    expect(find.bySemanticsLabel(RegExp('Mercato del Borgo')), findsOneWidget);

    await tester.tap(find.byType(TransactionRow));
    expect(taps, 1);
    semantics.dispose();
  });

  group('with the text at 200%', () {
    testWidgets('the transaction row puts the amount under the texts', (
      tester,
    ) async {
      await pumpInTheme(
        tester,
        _tealDark,
        const Material(
          child: TransactionRow(
            icon: Symbols.shopping_cart_rounded,
            counterparty: 'Mercato del Borgo',
            details: 'Spesa',
            amount: '−45,20 €',
          ),
        ),
        textScale: 2,
      );

      final counterparty = tester.getRect(find.text('Mercato del Borgo'));
      final amount = tester.getRect(find.text('−45,20 €'));
      expect(amount.top, greaterThanOrEqualTo(counterparty.bottom));
      expect(amount.left, counterparty.left);
      // The counterparty keeps the width of the row, minus the icon.
      final row = tester.getRect(find.byType(TransactionRow));
      expect(counterparty.width, greaterThan(row.width / 2));
    });

    testWidgets('the number tile keeps the amount on one line', (tester) async {
      const amount = '−1.312,75 €';
      await pumpInTheme(
        tester,
        _tealDark,
        const Row(
          children: [
            Expanded(
              child: NumberTile(label: 'Entrate', amount: '0,00 €'),
            ),
            Expanded(
              child: NumberTile(label: 'Uscite', amount: amount),
            ),
          ],
        ),
        textScale: 2,
      );

      final style = tester.widget<Text>(find.text(amount)).style!;
      final oneLine = 2 * style.fontSize! * style.height!;
      expect(tester.getSize(find.text(amount)).height, oneLine);
      expect(
        tester.getRect(find.text(amount)).right,
        lessThanOrEqualTo(tester.getRect(find.byType(NumberTile).last).right),
      );
    });

    testWidgets('the hub section card stops at 130%', (tester) async {
      await pumpInTheme(
        tester,
        _tealDark,
        HubSectionCard(
          icon: Symbols.account_balance_wallet_rounded,
          name: 'Finanze',
          onTap: () {},
        ),
        textScale: 2,
      );

      final scaler = MediaQuery.textScalerOf(
        tester.element(find.text('Finanze')),
      );
      expect(scaler.scale(10), closeTo(13, 1e-9));
    });

    testWidgets('the error of a text field wraps instead of being cut', (
      tester,
    ) async {
      const message = 'Scrivi un importo maggiore di zero';
      await pumpInTheme(
        tester,
        _tealDark,
        const Material(
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Importo',
              errorText: message,
            ),
          ),
        ),
        textScale: 2,
      );

      final style = Theme.of(tester.element(find.text(message))).textTheme;
      final oneLine = 2 * style.bodySmall!.fontSize! * style.bodySmall!.height!;
      expect(tester.getSize(find.text(message)).height, greaterThan(oneLine));
    });
  });

  group('balance bar', () {
    for (final (value, label, amount) in const [
      (0.6, 'Deve ricevere', '+62,00'),
      (-0.35, 'Deve alla casa', '−36,50'),
    ]) {
      testWidgets('$label: sign and words, not the colour alone', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpInTheme(
          tester,
          _tealLight,
          BalanceBar(value: value, label: label, amount: amount),
        );

        expect(find.text(label), findsOneWidget);
        expect(find.bySemanticsLabel('$label, $amount'), findsOneWidget);
        final colors = Theme.of(tester.element(find.byType(BalanceBar)))
            .extension<AppColors>()!;
        expect(
          tester.widget<Text>(find.text(amount)).style?.color,
          value < 0 ? colors.debito : colors.credito,
        );
        semantics.dispose();
      });
    }

    testWidgets('an even balance has the neutral colour', (tester) async {
      await pumpInTheme(
        tester,
        _tealLight,
        const BalanceBar(value: 0, label: 'In pari', amount: '0,00'),
      );
      expect(
        tester.widget<Text>(find.text('0,00')).style?.color,
        tealLight.onSurface,
      );
    });
  });

  group('numeric keypad', () {
    testWidgets('reports its twelve keys, each a touch target', (tester) async {
      final semantics = tester.ensureSemantics();
      final pressed = <String>[];
      await pumpInTheme(
        tester,
        _tealDark,
        NumericKeypad(
          onDigit: (digit) => pressed.add('$digit'),
          onDecimalSeparator: () => pressed.add(','),
          onBackspace: () => pressed.add('back'),
        ),
      );

      for (var digit = 0; digit <= 9; digit++) {
        final key = find.bySemanticsLabel('$digit');
        expect(key, findsOneWidget);
        await tester.tap(find.text('$digit'));
      }
      await tester.tap(find.bySemanticsLabel('Virgola'));
      await tester.tap(find.bySemanticsLabel('Cancella'));
      expect(pressed, [
        for (var digit = 0; digit <= 9; digit++) '$digit',
        ',',
        'back',
      ]);

      // Each key is a pill at least 48 × 48.
      final keys = find.descendant(
        of: find.byType(NumericKeypad),
        matching: find.byType(InkWell),
      );
      expect(keys, findsNWidgets(12));
      for (final element in keys.evaluate()) {
        expect(element.size, _isTouchTarget);
      }
      semantics.dispose();
    });

    testWidgets('a key without a callback is disabled', (tester) async {
      final pressed = <int>[];
      await pumpInTheme(
        tester,
        _tealDark,
        NumericKeypad(
          onDigit: pressed.add,
          onDecimalSeparator: null,
          onBackspace: null,
        ),
      );

      await tester.tap(find.text(','));
      await tester.tap(find.byIcon(Symbols.backspace_rounded));
      await tester.tap(find.text('7'));
      expect(pressed, [7]);
    });
  });

  testWidgets('palette row: three dots, the name and a radio', (tester) async {
    final semantics = tester.ensureSemantics();
    AppPalette? chosen = AppPalette.teal;
    await pumpInTheme(
      tester,
      _tealDark,
      StatefulBuilder(
        builder: (context, setState) => RadioGroup<AppPalette>(
          groupValue: chosen,
          onChanged: (palette) => setState(() => chosen = palette),
          child: Column(
            children: [
              for (final palette in AppPalette.values)
                PaletteRadioTile(palette: palette),
            ],
          ),
        ),
      ),
    );

    for (final palette in AppPalette.values) {
      expect(find.text(palette.label), findsOneWidget);
      expect(
        tester.getSize(find.byType(PaletteRadioTile).at(palette.index)),
        _isTouchTarget,
      );
    }
    await tester.tap(find.text(AppPalette.dollari.label));
    await tester.pumpAndSettle();
    expect(chosen, AppPalette.dollari);
    semantics.dispose();
  });

  group('list rows paint their title in onSurface', () {
    // The style a Text paints with: its own, merged with the inherited one.
    Color? paintedColor(WidgetTester tester, String text) => tester
        .widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .text
        .style
        ?.color;

    for (final combination in combinations) {
      testWidgets(describeCombination(combination), (tester) async {
        await pumpInTheme(
          tester,
          combination,
          RadioGroup<AppPalette>(
            groupValue: AppPalette.teal,
            onChanged: (_) {},
            child: Column(
              children: [
                const PaletteRadioTile(palette: AppPalette.dollari),
                SwitchListTile(
                  title: const Text('Notifiche'),
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        );

        final onSurface = tokensOf(combination.$1, combination.$2).onSurface;
        expect(paintedColor(tester, AppPalette.dollari.label), onSurface);
        expect(paintedColor(tester, 'Notifiche'), onSurface);
      });
    }
  });
}
