import 'dart:ui';

/// Fixed palettes of the app (section 1 of `docs/spec/stile.md`).
enum AppPalette {
  teal('Teal'),
  dollari('Dollari'),
  mauriziani('Soldi mauriziani');

  new(this.label);

  /// Italian name shown in the interface.
  final String label;
}

/// Colour tokens of one palette in one brightness.
///
/// Field names and values are copied from section 2.1 of
/// `docs/spec/stile.md`; a test keeps this file and that table in sync.
class PaletteTokens {
  const new({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.shadow,
    required this.scrim,
    required this.surfaceTint,
    required this.testoTerziario,
    required this.banda,
    required this.suPrimarioTenue,
    required this.avviso,
    required this.credito,
    required this.debito,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
  final Color shadow;
  final Color scrim;
  final Color surfaceTint;
  final Color testoTerziario;
  final Color banda;
  final Color suPrimarioTenue;
  final Color avviso;
  final Color credito;
  final Color debito;

  /// Tokens by role name, as written in the specification table.
  Map<String, Color> get byRole => {
    'primary': primary,
    'onPrimary': onPrimary,
    'primaryContainer': primaryContainer,
    'onPrimaryContainer': onPrimaryContainer,
    'secondary': secondary,
    'onSecondary': onSecondary,
    'secondaryContainer': secondaryContainer,
    'onSecondaryContainer': onSecondaryContainer,
    'tertiary': tertiary,
    'onTertiary': onTertiary,
    'tertiaryContainer': tertiaryContainer,
    'onTertiaryContainer': onTertiaryContainer,
    'error': error,
    'onError': onError,
    'errorContainer': errorContainer,
    'onErrorContainer': onErrorContainer,
    'surface': surface,
    'onSurface': onSurface,
    'onSurfaceVariant': onSurfaceVariant,
    'surfaceContainerLowest': surfaceContainerLowest,
    'surfaceContainerLow': surfaceContainerLow,
    'surfaceContainer': surfaceContainer,
    'surfaceContainerHigh': surfaceContainerHigh,
    'surfaceContainerHighest': surfaceContainerHighest,
    'surfaceDim': surfaceDim,
    'surfaceBright': surfaceBright,
    'outline': outline,
    'outlineVariant': outlineVariant,
    'inverseSurface': inverseSurface,
    'onInverseSurface': onInverseSurface,
    'inversePrimary': inversePrimary,
    'shadow': shadow,
    'scrim': scrim,
    'surfaceTint': surfaceTint,
    'testoTerziario': testoTerziario,
    'banda': banda,
    'suPrimarioTenue': suPrimarioTenue,
    'avviso': avviso,
    'credito': credito,
    'debito': debito,
  };
}

/// Light and dark tokens of a palette.
typedef PaletteVariants = ({PaletteTokens light, PaletteTokens dark});

const tealDark = PaletteTokens(
  primary: Color(0xFFA6EEF6),
  onPrimary: Color(0xFF00363C),
  primaryContainer: Color(0xFF00666F),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFFA6EEF6),
  onSecondary: Color(0xFF00363C),
  secondaryContainer: Color(0xFF1F4E53),
  onSecondaryContainer: Color(0xFFE3F1F2),
  tertiary: Color(0xFFA6EEF6),
  onTertiary: Color(0xFF00363C),
  tertiaryContainer: Color(0xFFA6EEF6),
  onTertiaryContainer: Color(0xFF00363C),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF161A1A),
  onSurface: Color(0xFFE3F1F2),
  onSurfaceVariant: Color(0xFFA9C2C5),
  surfaceContainerLowest: Color(0xFF161A1A),
  surfaceContainerLow: Color(0xFF1A2526),
  surfaceContainer: Color(0xFF1C2C2E),
  surfaceContainerHigh: Color(0xFF1E3336),
  surfaceContainerHighest: Color(0xFF24393C),
  surfaceDim: Color(0xFF161A1A),
  surfaceBright: Color(0xFF24393C),
  outline: Color(0xFF5E7477),
  outlineVariant: Color(0xFF24393C),
  inverseSurface: Color(0xFFE3F1F2),
  onInverseSurface: Color(0xFF161A1A),
  inversePrimary: Color(0xFF00666F),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF8EA1A4),
  banda: Color(0xFF007781),
  suPrimarioTenue: Color(0xFFCDF5F9),
  avviso: Color(0xFFE8C872),
  credito: Color(0xFFA6EEF6),
  debito: Color(0xFFFFB4AB),
);

const tealLight = PaletteTokens(
  primary: Color(0xFF006A73),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF00666F),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFF006A73),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFBFE6EA),
  onSecondaryContainer: Color(0xFF161D1D),
  tertiary: Color(0xFFA6EEF6),
  onTertiary: Color(0xFF00363C),
  tertiaryContainer: Color(0xFFA6EEF6),
  onTertiaryContainer: Color(0xFF00363C),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  surface: Color(0xFFF4FBFA),
  onSurface: Color(0xFF161D1D),
  onSurfaceVariant: Color(0xFF3F5052),
  surfaceContainerLowest: Color(0xFFF4FBFA),
  surfaceContainerLow: Color(0xFFE7F1F0),
  surfaceContainer: Color(0xFFE0EDEC),
  surfaceContainerHigh: Color(0xFFDAE9E8),
  surfaceContainerHighest: Color(0xFFCBE0DE),
  surfaceDim: Color(0xFFCBE0DE),
  surfaceBright: Color(0xFFF4FBFA),
  outline: Color(0xFF6F8385),
  outlineVariant: Color(0xFFCBDCDB),
  inverseSurface: Color(0xFF161D1D),
  onInverseSurface: Color(0xFFF4FBFA),
  inversePrimary: Color(0xFFA6EEF6),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF566A6C),
  banda: Color(0xFF007781),
  suPrimarioTenue: Color(0xFFCDF5F9),
  avviso: Color(0xFF765500),
  credito: Color(0xFF006A73),
  debito: Color(0xFFBA1A1A),
);

const dollariDark = PaletteTokens(
  primary: Color(0xFFB5E8A9),
  onPrimary: Color(0xFF0E3815),
  primaryContainer: Color(0xFF2F6B3E),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFFB5E8A9),
  onSecondary: Color(0xFF0E3815),
  secondaryContainer: Color(0xFF2A4F31),
  onSecondaryContainer: Color(0xFFE5F1E5),
  tertiary: Color(0xFFB5E8A9),
  onTertiary: Color(0xFF0E3815),
  tertiaryContainer: Color(0xFFB5E8A9),
  onTertiaryContainer: Color(0xFF0E3815),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF161A17),
  onSurface: Color(0xFFE5F1E5),
  onSurfaceVariant: Color(0xFFAFC4B0),
  surfaceContainerLowest: Color(0xFF161A17),
  surfaceContainerLow: Color(0xFF1B251D),
  surfaceContainer: Color(0xFF1E2C21),
  surfaceContainerHigh: Color(0xFF213425),
  surfaceContainerHighest: Color(0xFF283D2C),
  surfaceDim: Color(0xFF161A17),
  surfaceBright: Color(0xFF283D2C),
  outline: Color(0xFF63776A),
  outlineVariant: Color(0xFF283D2C),
  inverseSurface: Color(0xFFE5F1E5),
  onInverseSurface: Color(0xFF161A17),
  inversePrimary: Color(0xFF2F6B3E),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF94A595),
  banda: Color(0xFF387647),
  suPrimarioTenue: Color(0xFFD3F2D6),
  avviso: Color(0xFFE8C872),
  credito: Color(0xFFB5E8A9),
  debito: Color(0xFFFFB4AB),
);

const dollariLight = PaletteTokens(
  primary: Color(0xFF2F6B3E),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF2F6B3E),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFF2F6B3E),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFC6E6C0),
  onSecondaryContainer: Color(0xFF171D17),
  tertiary: Color(0xFFB5E8A9),
  onTertiary: Color(0xFF0E3815),
  tertiaryContainer: Color(0xFFB5E8A9),
  onTertiaryContainer: Color(0xFF0E3815),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  surface: Color(0xFFF5FBF4),
  onSurface: Color(0xFF171D17),
  onSurfaceVariant: Color(0xFF41524A),
  surfaceContainerLowest: Color(0xFFF5FBF4),
  surfaceContainerLow: Color(0xFFE8F2E7),
  surfaceContainer: Color(0xFFE1EEE0),
  surfaceContainerHigh: Color(0xFFDBEADA),
  surfaceContainerHighest: Color(0xFFCCE0CB),
  surfaceDim: Color(0xFFCCE0CB),
  surfaceBright: Color(0xFFF5FBF4),
  outline: Color(0xFF71857A),
  outlineVariant: Color(0xFFCCDDCB),
  inverseSurface: Color(0xFF171D17),
  onInverseSurface: Color(0xFFF5FBF4),
  inversePrimary: Color(0xFFB5E8A9),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF566B59),
  banda: Color(0xFF387647),
  suPrimarioTenue: Color(0xFFD3F2D6),
  avviso: Color(0xFF765500),
  credito: Color(0xFF2F6B3E),
  debito: Color(0xFFBA1A1A),
);

const maurizianiDark = PaletteTokens(
  primary: Color(0xFFD6C2FF),
  onPrimary: Color(0xFF33175E),
  primaryContainer: Color(0xFF5B3F8C),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFFD6C2FF),
  onSecondary: Color(0xFF33175E),
  secondaryContainer: Color(0xFF43345C),
  onSecondaryContainer: Color(0xFFEDE6F4),
  tertiary: Color(0xFFD6C2FF),
  onTertiary: Color(0xFF33175E),
  tertiaryContainer: Color(0xFFD6C2FF),
  onTertiaryContainer: Color(0xFF33175E),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF18161C),
  onSurface: Color(0xFFEDE6F4),
  onSurfaceVariant: Color(0xFFBDB2CC),
  surfaceContainerLowest: Color(0xFF18161C),
  surfaceContainerLow: Color(0xFF221E29),
  surfaceContainer: Color(0xFF26212E),
  surfaceContainerHigh: Color(0xFF2A2434),
  surfaceContainerHighest: Color(0xFF332C3F),
  surfaceDim: Color(0xFF18161C),
  surfaceBright: Color(0xFF332C3F),
  outline: Color(0xFF6F667E),
  outlineVariant: Color(0xFF332C3F),
  inverseSurface: Color(0xFFEDE6F4),
  onInverseSurface: Color(0xFF18161C),
  inversePrimary: Color(0xFF5B3F8C),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF938AA2),
  banda: Color(0xFF6B4CA0),
  suPrimarioTenue: Color(0xFFE6DAFB),
  avviso: Color(0xFFE8C872),
  credito: Color(0xFFD6C2FF),
  debito: Color(0xFFFFB4AB),
);

const maurizianiLight = PaletteTokens(
  primary: Color(0xFF5B3F8C),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF5B3F8C),
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary: Color(0xFF5B3F8C),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE2D4FB),
  onSecondaryContainer: Color(0xFF1D1A22),
  tertiary: Color(0xFFD6C2FF),
  onTertiary: Color(0xFF33175E),
  tertiaryContainer: Color(0xFFD6C2FF),
  onTertiaryContainer: Color(0xFF33175E),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  surface: Color(0xFFFBF8FE),
  onSurface: Color(0xFF1D1A22),
  onSurfaceVariant: Color(0xFF4C4459),
  surfaceContainerLowest: Color(0xFFFBF8FE),
  surfaceContainerLow: Color(0xFFF0EBF7),
  surfaceContainer: Color(0xFFEBE4F4),
  surfaceContainerHigh: Color(0xFFE6DEF1),
  surfaceContainerHighest: Color(0xFFDAD0E9),
  surfaceDim: Color(0xFFDAD0E9),
  surfaceBright: Color(0xFFFBF8FE),
  outline: Color(0xFF7B7289),
  outlineVariant: Color(0xFFDDD5E8),
  inverseSurface: Color(0xFF1D1A22),
  onInverseSurface: Color(0xFFFBF8FE),
  inversePrimary: Color(0xFFD6C2FF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
  testoTerziario: Color(0xFF655C73),
  banda: Color(0xFF6B4CA0),
  suPrimarioTenue: Color(0xFFE6DAFB),
  avviso: Color(0xFF765500),
  credito: Color(0xFF5B3F8C),
  debito: Color(0xFFBA1A1A),
);

const paletteTokens = <AppPalette, PaletteVariants>{
  AppPalette.teal: (light: tealLight, dark: tealDark),
  AppPalette.dollari: (light: dollariLight, dark: dollariDark),
  AppPalette.mauriziani: (light: maurizianiLight, dark: maurizianiDark),
};

/// Tokens of [palette] in [brightness].
PaletteTokens tokensOf(AppPalette palette, Brightness brightness) {
  final variants = paletteTokens[palette]!;
  return brightness == Brightness.dark ? variants.dark : variants.light;
}

// Fixed colours, the same for every palette (section 2.1).

/// Construction-site tape.
const nastroGiallo = Color(0xFFFFC83D);
const nastroNero = Color(0xFF1F1F1F);

/// Counter badge in the dark theme; the light theme uses `error` and
/// `onError`.
const counterBadgeDark = Color(0xFFFFB4AB);
const onCounterBadgeDark = Color(0xFF690005);

/// Colour roles of the hub house (section 9.2), with the names of the
/// specification.
enum CasaRole {
  ombra,
  terra,
  terraFronte,
  terraLato,
  muro,
  muroOmbra,
  muroLuce,
  cornice,
  ringhiera,
  tetto,
  tettoOmbra,
  timpano,
  buioFondo,
  buioLato,
  buioPav,
  accFondo,
  accLato,
  accPav,
  vetroAcceso,
  alone,
  arredo,
  arredoOmbra,
  arredoChiaro,
  arredoLuce,
  mobile,
  mobileScuro,
  vetroSpento,
  vetroScuro,
  porta,
  accento,
  accento2,
  verde,
  verdeLuce,
  pianta,
  cucciaTetto,
  banda1,
  banda2,
  stelle,
}

/// The house roles of the Teal palette at night: the base every other
/// combination is computed from (section 9.2).
const casaTealNight = <CasaRole, Color>{
  CasaRole.ombra: Color(0xFF0A1011),
  CasaRole.terra: Color(0xFF173B3E),
  CasaRole.terraFronte: Color(0xFF0D2729),
  CasaRole.terraLato: Color(0xFF0A1F21),
  CasaRole.muro: Color(0xFF1E3A3D),
  CasaRole.muroOmbra: Color(0xFF162D30),
  CasaRole.muroLuce: Color(0xFF2B4A4E),
  CasaRole.cornice: Color(0xFF3E6A6F),
  CasaRole.ringhiera: Color(0xFF6E979B),
  CasaRole.tetto: Color(0xFF00666F),
  CasaRole.tettoOmbra: Color(0xFF003D44),
  CasaRole.timpano: Color(0xFF00525A),
  CasaRole.buioFondo: Color(0xFF1A2A2C),
  CasaRole.buioLato: Color(0xFF152325),
  CasaRole.buioPav: Color(0xFF203335),
  CasaRole.accFondo: Color(0xFF2F7177),
  CasaRole.accLato: Color(0xFF28656B),
  CasaRole.accPav: Color(0xFF3A8A90),
  CasaRole.vetroAcceso: Color(0xFFD2F7FB),
  CasaRole.alone: Color(0xFFA6EEF6),
  CasaRole.arredo: Color(0xFF2A4245),
  CasaRole.arredoOmbra: Color(0xFF203538),
  CasaRole.arredoChiaro: Color(0xFF3A5558),
  CasaRole.arredoLuce: Color(0xFF4E6B6E),
  CasaRole.mobile: Color(0xFF0F3337),
  CasaRole.mobileScuro: Color(0xFF0B2427),
  CasaRole.vetroSpento: Color(0xFF24393C),
  CasaRole.vetroScuro: Color(0xFF0F2326),
  CasaRole.porta: Color(0xFF00525A),
  CasaRole.accento: Color(0xFFA6EEF6),
  CasaRole.accento2: Color(0xFF7FD4DE),
  CasaRole.verde: Color(0xFF1F5A5F),
  CasaRole.verdeLuce: Color(0xFF2A6E73),
  CasaRole.pianta: Color(0xFF1F4A4E),
  CasaRole.cucciaTetto: Color(0xFF245A5F),
  CasaRole.banda1: Color(0xFF00444B),
  CasaRole.banda2: Color(0xFF005A63),
  CasaRole.stelle: Color(0xFFC2D6D8),
};

/// Colour that dawn and sunset lean towards (section 9.2).
const casaSunset = Color(0xFFE07A3C);
