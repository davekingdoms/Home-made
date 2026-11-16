import 'package:homemade/theme/tokens.dart' as tokens;
import 'package:material_ui/material_ui.dart';

/// Colour roles that Material 3 does not have (sections 2.1 and 10 of
/// `docs/spec/stile.md`). Field names are the token names of the
/// specification, kept in Italian on purpose; the counter badge has no name
/// there.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const new({
    required this.testoTerziario,
    required this.banda,
    required this.suPrimarioTenue,
    required this.avviso,
    required this.credito,
    required this.debito,
    required this.nastroGiallo,
    required this.nastroNero,
    required this.badge,
    required this.onBadge,
  });

  factory fromTokens(tokens.PaletteTokens t, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppColors(
      testoTerziario: t.testoTerziario,
      banda: t.banda,
      suPrimarioTenue: t.suPrimarioTenue,
      avviso: t.avviso,
      credito: t.credito,
      debito: t.debito,
      nastroGiallo: tokens.nastroGiallo,
      nastroNero: tokens.nastroNero,
      badge: dark ? tokens.counterBadgeDark : t.error,
      onBadge: dark ? tokens.onCounterBadgeDark : t.onError,
    );
  }

  /// Third level of text, after `onSurface` and `onSurfaceVariant`. Never on
  /// `surfaceContainerHighest` (section 2.2).
  final Color testoTerziario;

  /// Diagonal band over `primaryContainer`.
  final Color banda;

  /// Subdued text over `primaryContainer`.
  final Color suPrimarioTenue;

  /// Warning icons and texts.
  final Color avviso;

  /// Credit in balances and settlement: never the only signal.
  final Color credito;

  /// Debt in balances and settlement: never the only signal.
  final Color debito;

  /// Construction-site tape.
  final Color nastroGiallo;
  final Color nastroNero;

  /// Counter badge and its text.
  final Color badge;
  final Color onBadge;

  @override
  AppColors copyWith({
    Color? testoTerziario,
    Color? banda,
    Color? suPrimarioTenue,
    Color? avviso,
    Color? credito,
    Color? debito,
    Color? nastroGiallo,
    Color? nastroNero,
    Color? badge,
    Color? onBadge,
  }) => AppColors(
    testoTerziario: testoTerziario ?? this.testoTerziario,
    banda: banda ?? this.banda,
    suPrimarioTenue: suPrimarioTenue ?? this.suPrimarioTenue,
    avviso: avviso ?? this.avviso,
    credito: credito ?? this.credito,
    debito: debito ?? this.debito,
    nastroGiallo: nastroGiallo ?? this.nastroGiallo,
    nastroNero: nastroNero ?? this.nastroNero,
    badge: badge ?? this.badge,
    onBadge: onBadge ?? this.onBadge,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      testoTerziario: Color.lerp(testoTerziario, other.testoTerziario, t)!,
      banda: Color.lerp(banda, other.banda, t)!,
      suPrimarioTenue: Color.lerp(suPrimarioTenue, other.suPrimarioTenue, t)!,
      avviso: Color.lerp(avviso, other.avviso, t)!,
      credito: Color.lerp(credito, other.credito, t)!,
      debito: Color.lerp(debito, other.debito, t)!,
      nastroGiallo: Color.lerp(nastroGiallo, other.nastroGiallo, t)!,
      nastroNero: Color.lerp(nastroNero, other.nastroNero, t)!,
      badge: Color.lerp(badge, other.badge, t)!,
      onBadge: Color.lerp(onBadge, other.onBadge, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The [AppColors] of the current theme.
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
