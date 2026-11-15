import 'package:homemade/theme/tokens.dart' as tokens;
import 'package:material_ui/material_ui.dart';

/// Colour roles that Material 3 does not have (section 10 of
/// `docs/spec/stile.md`). Field names are the token names of the
/// specification, kept in Italian on purpose.
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
  });

  factory fromTokens(tokens.PaletteTokens t) => AppColors(
    testoTerziario: t.testoTerziario,
    banda: t.banda,
    suPrimarioTenue: t.suPrimarioTenue,
    avviso: t.avviso,
    credito: t.credito,
    debito: t.debito,
    nastroGiallo: tokens.nastroGiallo,
    nastroNero: tokens.nastroNero,
  );

  final Color testoTerziario;
  final Color banda;
  final Color suPrimarioTenue;
  final Color avviso;
  final Color credito;
  final Color debito;
  final Color nastroGiallo;
  final Color nastroNero;

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
  }) => AppColors(
    testoTerziario: testoTerziario ?? this.testoTerziario,
    banda: banda ?? this.banda,
    suPrimarioTenue: suPrimarioTenue ?? this.suPrimarioTenue,
    avviso: avviso ?? this.avviso,
    credito: credito ?? this.credito,
    debito: debito ?? this.debito,
    nastroGiallo: nastroGiallo ?? this.nastroGiallo,
    nastroNero: nastroNero ?? this.nastroNero,
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
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The [AppColors] of the current theme.
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
