/// Catalog of every screen and bottom sheet of the app, from
/// `docs/spec/navigazione.md`. Routes, placeholders, the screen index and the
/// tests all read it.
library;

/// Navigation level of a screen (section 1 of the specification).
enum ScreenLevel {
  /// Level 0: no bottom bar.
  global('Livello 0 · globale'),

  /// Level 1: a tab of a section, with the bottom bar.
  section('Livello 1 · schede di Finanze'),

  /// Level 2: full screen above the section.
  detail('Livello 2 · dettagli'),

  /// Level 3: modal bottom sheet, not a route.
  sheet('Livello 3 · fogli dal basso');

  new(this.title);

  final String title;
}

/// Identifier used in place of route parameters: never readable data.
const exampleId = 'example';

/// Values of `:kind` in the New entry route (F2), with their Italian names.
const newEntryKinds = <String, String>{
  'cash-expense': 'Spesa in contanti',
  'income': 'Entrata',
  'transfer': 'Trasferimento',
};

class ScreenEntry {
  const new(
    this.code,
    this.title,
    this.level, {
    this.path,
    this.opens = const [],
    this.opensOnTop = false,
  });

  /// Inventory code (A1–I10).
  final String code;

  /// Italian title shown in the interface.
  final String title;

  final ScreenLevel level;

  /// Route path; null for bottom sheets, which are not routes.
  final String? path;

  /// Codes of the screens and sheets reachable from here: the "Si apre da"
  /// column of the specification, read backwards.
  final List<String> opens;

  /// Whether the route is pushed on top of the current screen instead of
  /// rebuilding the stack from its path.
  final bool opensOnTop;

  bool get isSheet => level == ScreenLevel.sheet;

  /// Text of the placeholder title: "‹code› · ‹title›".
  String get label => '$code · $title';

  /// Example locations with their link labels: one per `:kind`, otherwise
  /// a single one with [exampleId] in place of the parameters.
  Map<String, String> get exampleLocations {
    final path = this.path;
    if (path == null) return const {};
    if (path.contains(':kind')) {
      return {
        for (final kind in newEntryKinds.entries)
          path.replaceFirst(':kind', kind.key): '$label · ${kind.value}',
      };
    }
    return {path.replaceAll(RegExp(r':\w+'), exampleId): label};
  }

  /// First example location; null for bottom sheets.
  String? get location => exampleLocations.keys.firstOrNull;
}

const screenCatalog = <ScreenEntry>[
  // Level 0
  ScreenEntry('A1', 'Sblocco', ScreenLevel.global, path: '/unlock'),
  ScreenEntry(
    'A2',
    'Accesso',
    ScreenLevel.global,
    path: '/sign-in',
    opens: ['A3'],
  ),
  ScreenEntry(
    'A3',
    'Primo accesso',
    ScreenLevel.global,
    path: '/welcome',
    opens: ['A7'],
  ),
  ScreenEntry(
    'A7',
    'Crea o entra in una casa',
    ScreenLevel.global,
    path: '/household',
    opens: ['A8', 'A10'],
  ),
  ScreenEntry(
    'A8',
    'Crea casa',
    ScreenLevel.global,
    path: '/household/create',
    opens: ['A9'],
  ),
  ScreenEntry('A9', 'Invita', ScreenLevel.global, path: '/household/invite'),
  ScreenEntry(
    'A10',
    'Entra con invito',
    ScreenLevel.global,
    path: '/household/join',
  ),
  ScreenEntry('B1', 'Hub', ScreenLevel.global, path: '/', opens: ['C1', 'I1']),
  ScreenEntry(
    'I1',
    'Impostazioni',
    ScreenLevel.global,
    path: '/settings',
    opens: ['I2', 'I3', 'I4', 'I5', 'I9', 'I10'],
  ),
  ScreenEntry(
    'I2',
    'Account',
    ScreenLevel.global,
    path: '/settings/account',
    opens: ['A2'],
  ),
  ScreenEntry(
    'I3',
    'Aspetto',
    ScreenLevel.global,
    path: '/settings/appearance',
  ),
  ScreenEntry(
    'I4',
    'Casa',
    ScreenLevel.global,
    path: '/settings/household',
    opens: ['A9'],
  ),
  ScreenEntry(
    'I5',
    'Impostazioni Finanze',
    ScreenLevel.global,
    path: '/settings/finance',
    opens: ['I6', 'I7', 'I8'],
  ),
  ScreenEntry(
    'I6',
    'Categorie',
    ScreenLevel.global,
    path: '/settings/finance/categories',
  ),
  ScreenEntry('I7', 'Tag', ScreenLevel.global, path: '/settings/finance/tags'),
  ScreenEntry(
    'I8',
    'Rubrica persone esterne',
    ScreenLevel.global,
    path: '/settings/finance/people',
  ),
  ScreenEntry(
    'I9',
    'Sicurezza, notifiche, info',
    ScreenLevel.global,
    path: '/settings/security',
  ),
  ScreenEntry('I10', 'Hub', ScreenLevel.global, path: '/settings/hub'),

  // Level 1: Finance tabs. The "+" button of C1 and D1 opens F1.
  ScreenEntry(
    'C1',
    'Riepilogo',
    ScreenLevel.section,
    path: '/finance/summary',
    opens: ['C2', 'C4', 'H1'],
  ),
  ScreenEntry(
    'D1',
    'Movimenti',
    ScreenLevel.section,
    path: '/finance/transactions',
    opens: ['E1', 'D2'],
  ),
  ScreenEntry(
    'G1',
    'Analisi',
    ScreenLevel.section,
    path: '/finance/analytics',
    opens: ['G2'],
  ),
  ScreenEntry(
    'H1',
    'I tuoi conti',
    ScreenLevel.section,
    path: '/finance/accounts',
    opens: ['H2', 'H4', 'H5'],
  ),

  // Level 2: details
  ScreenEntry(
    'C2',
    'Saldi',
    ScreenLevel.detail,
    path: '/finance/summary/balances',
    opens: ['C3'],
  ),
  ScreenEntry(
    'C3',
    'Dettaglio persona',
    ScreenLevel.detail,
    path: '/finance/summary/balances/people/:personId',
  ),
  ScreenEntry(
    'C4',
    'Salvadanai',
    ScreenLevel.detail,
    path: '/finance/summary/savings',
  ),
  ScreenEntry(
    'E1',
    'Dettaglio transazione',
    ScreenLevel.detail,
    path: '/finance/transactions/:transactionId',
    opens: ['E2', 'E3', 'E4', 'E5'],
  ),
  ScreenEntry(
    'F2',
    'Nuovo movimento',
    ScreenLevel.detail,
    path: '/finance/new/:kind',
    opens: ['E2', 'E3'],
    opensOnTop: true,
  ),
  ScreenEntry(
    'G2',
    'Report',
    ScreenLevel.detail,
    path: '/finance/analytics/reports',
  ),
  ScreenEntry(
    'H2',
    'Dettaglio conto',
    ScreenLevel.detail,
    path: '/finance/accounts/:accountId',
    opens: ['H3'],
  ),
  ScreenEntry(
    'H4',
    'Collega banca',
    ScreenLevel.detail,
    path: '/finance/accounts/link',
  ),
  ScreenEntry(
    'H5',
    'Conto manuale',
    ScreenLevel.detail,
    path: '/finance/accounts/new',
  ),

  // Level 3: bottom sheets
  ScreenEntry('D2', 'Filtri', ScreenLevel.sheet),
  ScreenEntry('E2', 'Scelta categoria', ScreenLevel.sheet),
  ScreenEntry('E3', 'Ripartizione', ScreenLevel.sheet),
  ScreenEntry('E4', 'Rimborsabile da terzi', ScreenLevel.sheet),
  ScreenEntry('E5', 'Tipo di movimento', ScreenLevel.sheet),
  ScreenEntry('F1', 'Menu "+"', ScreenLevel.sheet, opens: ['F2']),
  ScreenEntry('H3', 'Riconciliazione contanti', ScreenLevel.sheet),
];

/// The catalog entry with the given inventory [code].
ScreenEntry screenByCode(String code) =>
    screenCatalog.firstWhere((entry) => entry.code == code);
