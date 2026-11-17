import 'dart:async';

import 'package:homemade/core/money/money.dart';
import 'package:homemade/design/balance_bar.dart';
import 'package:homemade/design/chip_arrow_label.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/design/diagonal_band.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/design/hub_section_card.dart';
import 'package:homemade/design/notice_card.dart';
import 'package:homemade/design/number_tile.dart';
import 'package:homemade/design/numeric_keypad.dart';
import 'package:homemade/design/palette_radio_tile.dart';
import 'package:homemade/design/quick_tiles.dart';
import 'package:homemade/design/transaction_row.dart';
import 'package:homemade/theme/app_button_styles.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/app_text_theme.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// A component of section 8 of `docs/spec/stile.md`, shown with invented
/// data in the component catalog and in the golden tests.
class CatalogEntry {
  const new(this.id, this.title, this.builder, {this.hasText = true});

  /// Name of the golden files, in English.
  final String id;

  /// Italian name, as in the specification.
  final String title;

  final WidgetBuilder builder;

  /// Whether it also gets a golden image with the text at 200%.
  final bool hasText;
}

/// Every component of the table in section 8, except the hub house, which
/// waits for its specification.
const componentCatalog = <CatalogEntry>[
  CatalogEntry('navigation_bar', 'Barra di navigazione', _navigationBar),
  CatalogEntry('top_bar', 'Barra in alto', _topBar),
  CatalogEntry('filled_button', 'Bottone principale', _filledButton),
  CatalogEntry('tonal_button', 'Bottone tonale', _tonalButton),
  CatalogEntry('outlined_button', 'Bottone con contorno', _outlinedButton),
  CatalogEntry('text_button', 'Bottone di testo', _textButton),
  CatalogEntry('fab', 'FAB "+"', _fab, hasText: false),
  CatalogEntry('segmented_button', 'Segmented button', _segmentedButton),
  CatalogEntry('chip', 'Chip filtro', _chip),
  CatalogEntry('switch', 'Interruttore', _switch),
  CatalogEntry('radio', 'Radio', _radio),
  CatalogEntry('text_field', 'Campo di testo', _textField),
  CatalogEntry('bottom_sheet', 'Foglio dal basso', _bottomSheet),
  CatalogEntry('notice', 'Avviso', _notice),
  CatalogEntry('card', 'Card', _card),
  CatalogEntry('hub_section_card', "Card sezione dell'hub", _hubSectionCard),
  CatalogEntry('quick_tiles', 'Tessere rapide', _quickTiles),
  CatalogEntry('number_tile', 'Tessera numerica', _numberTile),
  CatalogEntry('transaction_row', 'Riga movimento', _transactionRow),
  CatalogEntry('balance_bar', 'Barra dei Saldi', _balanceBar),
  CatalogEntry('numeric_keypad', 'Tastierino numerico', _numericKeypad),
  CatalogEntry('refresh_indicator', 'Trascina per aggiornare', _refresh),
  CatalogEntry('cookie', 'Biscotto', _cookie),
  CatalogEntry('diagonal_band', 'Banda diagonale', _band, hasText: false),
];

// Invented data: example members, merchants and amounts.
const _members = ['Anna', 'Bruno', 'Carla'];
const _toClassify = 8;

void _noop() {}

/// A value that the demo of a component changes when it is used.
class _Demo<T> extends StatefulWidget {
  const new({required this.initial, required this.builder});

  final T initial;
  final Widget Function(BuildContext context, T value, ValueChanged<T> set)
  builder;

  @override
  State<_Demo<T>> createState() => _DemoState<T>();
}

class _DemoState<T> extends State<_Demo<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _value,
    (value) => setState(() => _value = value),
  );
}

/// The variants of a component, one under the other.
class _Variants extends StatelessWidget {
  const new(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    spacing: AppSpacing.sm,
    children: children,
  );
}

Widget _navigationBar(BuildContext context) => _Demo<int>(
  initial: 1,
  builder: (context, index, select) => NavigationBar(
    selectedIndex: index,
    onDestinationSelected: select,
    destinations: const [
      NavigationDestination(
        icon: Icon(Symbols.dashboard_rounded),
        selectedIcon: Icon(Symbols.dashboard_rounded, fill: 1),
        label: 'Riepilogo',
      ),
      NavigationDestination(
        icon: Badge(
          label: Text('$_toClassify'),
          child: Icon(Symbols.receipt_long_rounded),
        ),
        selectedIcon: Badge(
          label: Text('$_toClassify'),
          child: Icon(Symbols.receipt_long_rounded, fill: 1),
        ),
        label: 'Movimenti',
        tooltip: 'Movimenti, $_toClassify da classificare',
      ),
      NavigationDestination(
        icon: Icon(Symbols.insights_rounded),
        selectedIcon: Icon(Symbols.insights_rounded, fill: 1),
        label: 'Analisi',
      ),
      NavigationDestination(
        icon: Icon(Symbols.account_balance_rounded),
        selectedIcon: Icon(Symbols.account_balance_rounded, fill: 1),
        label: 'Conti',
      ),
    ],
  ),
);

Widget _topBar(BuildContext context) => _Variants([
  // Level 1: back to the hub.
  SizedBox(
    height: AppSizes.topBarHeight,
    child: AppBar(
      primary: false,
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.xxs,
      title: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _noop,
          icon: const Icon(Symbols.chevron_left_rounded),
          label: const Text('Finanze'),
        ),
      ),
    ),
  ),
  // Level 2: back arrow.
  SizedBox(
    height: AppSizes.topBarHeight,
    child: AppBar(
      primary: false,
      leading: const BackButton(onPressed: _noop),
      title: const Text('Dettaglio'),
    ),
  ),
]);

Widget _filledButton(BuildContext context) => _Variants([
  const FilledButton(onPressed: _noop, child: Text('Continua')),
  FilledButton(
    style: context.buttonStyles.compact,
    onPressed: _noop,
    child: const Text('Compatto'),
  ),
  FilledButton.icon(
    onPressed: _noop,
    icon: const Icon(Symbols.add_rounded),
    label: const Text('Nuovo movimento'),
  ),
  const FilledButton(onPressed: null, child: Text('Disattivato')),
]);

Widget _tonalButton(BuildContext context) => _Variants([
  FilledButton.tonal(
    style: context.buttonStyles.tonal,
    onPressed: _noop,
    child: const Text('Promemoria'),
  ),
  FilledButton.tonal(
    style: context.buttonStyles.tonal,
    onPressed: null,
    child: const Text('Disattivato'),
  ),
]);

Widget _outlinedButton(BuildContext context) => _Variants([
  const OutlinedButton(onPressed: _noop, child: Text('Annulla')),
  OutlinedButton(
    style: context.buttonStyles.destructive,
    onPressed: _noop,
    child: const Text('Esci'),
  ),
  const OutlinedButton(onPressed: null, child: Text('Disattivato')),
]);

Widget _textButton(BuildContext context) => const _Variants([
  TextButton(onPressed: _noop, child: Text('Saldi')),
  TextButton(onPressed: null, child: Text('Disattivato')),
]);

Widget _fab(BuildContext context) => const FloatingActionButton(
  heroTag: null,
  tooltip: 'Aggiungi',
  onPressed: _noop,
  child: Icon(Symbols.add_rounded),
);

Widget _segmentedButton(BuildContext context) => _Variants([
  _Demo<bool>(
    initial: true,
    builder: (context, mine, select) => SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Miei')),
        ButtonSegment(value: false, label: Text('Casa')),
      ],
      selected: {mine},
      onSelectionChanged: (selection) => select(selection.single),
    ),
  ),
  _Demo<int>(
    initial: 0,
    builder: (context, period, select) => SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('Mese')),
        ButtonSegment(value: 1, label: Text('Anno')),
        ButtonSegment(value: 2, label: Text('Tutto')),
      ],
      selected: {period},
      onSelectionChanged: (selection) => select(selection.single),
    ),
  ),
]);

Widget _chip(BuildContext context) => Wrap(
  spacing: AppSpacing.xs,
  runSpacing: AppSpacing.xs,
  children: [
    _Demo<bool>(
      initial: true,
      builder: (context, selected, select) => FilterChip(
        label: const Text('Da classificare'),
        selected: selected,
        onSelected: select,
      ),
    ),
    _Demo<bool>(
      initial: false,
      builder: (context, selected, select) => FilterChip(
        label: const Text('Condivise'),
        selected: selected,
        onSelected: select,
      ),
    ),
    const ActionChip(label: ChipArrowLabel('Questo mese'), onPressed: _noop),
    const ActionChip(label: ChipArrowLabel('Tutti i conti')),
  ],
);

Widget _switch(BuildContext context) => _Variants([
  _Demo<bool>(
    initial: true,
    builder: (context, on, set) => SwitchListTile(
      title: const Text('Notifiche'),
      value: on,
      onChanged: set,
    ),
  ),
  const SwitchListTile(
    title: Text('Disattivato'),
    value: false,
    onChanged: null,
  ),
]);

Widget _radio(BuildContext context) => _Demo<AppPalette>(
  initial: AppPalette.teal,
  builder: (context, palette, select) => RadioGroup<AppPalette>(
    groupValue: palette,
    onChanged: (value) => select(value ?? palette),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        for (final option in AppPalette.values)
          PaletteRadioTile(palette: option),
      ],
    ),
  ),
);

Widget _textField(BuildContext context) => const _Variants([
  TextField(decoration: InputDecoration(labelText: 'Descrizione')),
  TextField(
    decoration: InputDecoration(
      labelText: 'Importo',
      errorText: 'Scrivi un importo maggiore di zero',
    ),
  ),
  TextField(
    enabled: false,
    decoration: InputDecoration(labelText: 'Disattivato'),
  ),
]);

Widget _sheetContent(BuildContext context) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.screenMargin,
    0,
    AppSpacing.screenMargin,
    AppSpacing.xl,
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.sm,
    children: [
      Text('Categoria', style: Theme.of(context).textTheme.titleLarge),
      const Text('Scegli la categoria del movimento.'),
    ],
  ),
);

/// A bottom sheet as it looks when open, without a route under it.
class _SheetPreview extends StatefulWidget {
  const new();

  @override
  State<_SheetPreview> createState() => _SheetPreviewState();
}

class _SheetPreviewState extends State<_SheetPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      BottomSheet.createAnimationController(this)..value = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BottomSheet(
    animationController: _controller,
    // The preview stays in the list: dragging it scrolls the catalog.
    enableDrag: false,
    showDragHandle: true,
    // Dragging the preview closes nothing: it goes back in place.
    onClosing: () => _controller.value = 1,
    builder: _sheetContent,
  );
}

Widget _bottomSheet(BuildContext context) => _Variants([
  const _SheetPreview(),
  FilledButton.tonal(
    style: context.buttonStyles.tonal,
    onPressed: () => unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (context) => SafeArea(child: _sheetContent(context)),
      ),
    ),
    child: const Text('Apri il foglio'),
  ),
]);

Widget _notice(BuildContext context) => const _Variants([
  NoticeCard(
    kind: NoticeKind.error,
    title: 'Collegamento scaduto',
    subtitle: 'Collega di nuovo la Banca di prova.',
    actionLabel: 'Collega',
    onAction: _noop,
  ),
  NoticeCard(
    kind: NoticeKind.warning,
    title: 'Movimenti da classificare',
    subtitle: 'Ne restano $_toClassify di questo mese.',
    actionLabel: 'Apri',
    onAction: _noop,
  ),
  NoticeCard(
    kind: NoticeKind.info,
    title: 'Conguaglio in pari',
    subtitle: 'Nessuno deve niente alla casa.',
  ),
]);

Widget _card(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  return _Variants([
    Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Casa di prova', style: textTheme.titleMedium),
            Text(
              '${_members.length} membri',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
    HighlightCard(
      onTap: _noop,
      child: Builder(
        builder: (context) {
          // Inside the card the text styles are the white ones.
          final onCard = Theme.of(context).textTheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saldo della casa',
                style: onCard.titleMedium?.copyWith(
                  color: context.appColors.suPrimarioTenue,
                ),
              ),
              Text(
                const Money(184250).format(),
                style: onCard.headlineMedium?.amount,
              ),
            ],
          );
        },
      ),
    ),
  ]);
}

Widget _hubSectionCard(BuildContext context) => _Variants([
  HubSectionCard(
    icon: Symbols.account_balance_wallet_rounded,
    name: 'Finanze',
    status: '$_toClassify movimenti da classificare',
    facts: [
      HubQuickFact(value: const Money(184250).format(), label: 'Saldo'),
      HubQuickFact(
        value: const Money(-4520).format(sign: MoneySign.always),
        label: 'Conguaglio',
      ),
    ],
    onTap: _noop,
  ),
  const HubSectionCard(icon: Symbols.kitchen_rounded, name: 'Dispensa'),
]);

Widget _quickTiles(BuildContext context) => Wrap(
  spacing: AppSpacing.xs,
  runSpacing: AppSpacing.xs,
  children: [
    const CookieTile(
      count: _toClassify,
      label: 'da classificare',
      semanticLabel: '$_toClassify transazioni da classificare',
      onTap: _noop,
    ),
    PillTile(
      label: 'Contanti',
      value: const Money(3500).format(),
      onTap: _noop,
    ),
  ],
);

Widget _numberTile(BuildContext context) => Row(
  spacing: AppSpacing.xs,
  children: [
    Expanded(
      child: NumberTile(label: 'Entrate', amount: const Money(245000).format()),
    ),
    Expanded(
      child: NumberTile(label: 'Uscite', amount: const Money(-131275).format()),
    ),
  ],
);

Widget _transactionRow(BuildContext context) => Card(
  clipBehavior: Clip.antiAlias,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TransactionRow(
        icon: Symbols.shopping_cart_rounded,
        counterparty: 'Mercato del Borgo',
        details: 'Spesa · Carta di prova',
        amount: const Money(-4520).format(),
        onTap: _noop,
      ),
      TransactionRow(
        icon: Symbols.restaurant_rounded,
        counterparty: 'Trattoria della Piazza',
        details: 'Ristoranti · Contanti',
        amount: const Money(-3800).format(),
        onTap: _noop,
      ),
      TransactionRow(
        icon: Symbols.payments_rounded,
        counterparty: 'Stipendio di prova',
        amount: const Money(245000).format(),
      ),
    ],
  ),
);

Widget _balanceBar(BuildContext context) => _Variants([
  BalanceBar(
    value: 0.6,
    label: '${_members[0]} · Deve ricevere',
    amount: const Money(6200).format(sign: MoneySign.always),
  ),
  BalanceBar(
    value: -0.35,
    label: '${_members[1]} · Deve alla casa',
    amount: const Money(-3650).format(sign: MoneySign.always),
  ),
  BalanceBar(
    value: 0,
    label: '${_members[2]} · In pari',
    amount: const Money(0).format(sign: MoneySign.always),
  ),
]);

Widget _numericKeypad(BuildContext context) => _Demo<String>(
  initial: '12,5',
  builder: (context, typed, set) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.sm,
    children: [
      Text(
        typed.isEmpty ? '0' : typed,
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.displaySmall?.amount,
      ),
      NumericKeypad(
        onDigit: (digit) => set('$typed$digit'),
        onDecimalSeparator: typed.contains(',') ? null : () => set('$typed,'),
        onBackspace: typed.isEmpty
            ? null
            : () => set(typed.substring(0, typed.length - 1)),
      ),
    ],
  ),
);

// The catalog screen has the live one: pull the whole list down.
Widget _refresh(BuildContext context) => const _Variants([
  RefreshProgressIndicator(value: 0.7, semanticsLabel: 'Aggiornamento'),
  Text('Trascina il catalogo in basso per vederlo in azione.'),
]);

Widget _cookie(BuildContext context) => Wrap(
  spacing: AppSpacing.sm,
  runSpacing: AppSpacing.sm,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    for (final member in _members) CookieAvatar(name: member),
    CookieAvatar(name: _members.first, size: AppSizes.hubAvatar),
    const CookieCounter(
      count: _toClassify,
      semanticLabel: '$_toClassify transazioni da classificare',
    ),
  ],
);

Widget _band(BuildContext context) => SizedBox(
  height: AppSizes.listRowMinHeight * 2,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(AppRadii.card),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: DiagonalBand(color: context.appColors.banda),
    ),
  ),
);
