import 'dart:ui';

/// Fixed palettes of the app. Dollari and Soldi mauriziani arrive with the
/// settings: add a value here and its tokens to [paletteTokens].
enum AppPalette { teal }

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

const paletteTokens = <AppPalette, PaletteVariants>{
  AppPalette.teal: (light: tealLight, dark: tealDark),
};

/// Construction-site tape: fixed colours, the same for every palette.
const nastroGiallo = Color(0xFFFFC83D);
const nastroNero = Color(0xFF1F1F1F);
