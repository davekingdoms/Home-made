import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'appearance.g.dart';

/// Palette and theme chosen by the user (section 1 of
/// `docs/spec/stile.md`).
@immutable
class Appearance {
  const new({
    this.palette = AppPalette.teal,
    this.themeMode = ThemeMode.system,
  });

  final AppPalette palette;

  /// Automatico ([ThemeMode.system]), Chiaro or Scuro.
  final ThemeMode themeMode;

  Appearance copyWith({AppPalette? palette, ThemeMode? themeMode}) =>
      Appearance(
        palette: palette ?? this.palette,
        themeMode: themeMode ?? this.themeMode,
      );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.palette == palette &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(palette, themeMode);
}

/// Italian names of the theme modes.
extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'Automatico',
    ThemeMode.light => 'Chiaro',
    ThemeMode.dark => 'Scuro',
  };
}

/// The appearance of the whole app: Teal and Automatico until the user
/// chooses otherwise.
///
/// In memory only: the choice is saved with the Settings.
@Riverpod(keepAlive: true)
class AppearanceController extends _$AppearanceController {
  @override
  Appearance build() => const Appearance();

  void choosePalette(AppPalette palette) {
    state = state.copyWith(palette: palette);
  }

  void chooseThemeMode(ThemeMode themeMode) {
    state = state.copyWith(themeMode: themeMode);
  }
}
