/// Spacing, radii and sizes from section 4 of `docs/spec/stile.md`, in dp.
library;

/// Spacing on the 4 dp grid.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Side margin of the screens.
  static const double screenMargin = 16;

  /// Space between two cards.
  static const double cardGap = 12;

  /// Padding inside a card.
  static const double cardPadding = 16;

  /// Padding inside a card of the hub grid.
  static const double hubGridCardPadding = 14;

  /// Space between two sections of a screen (22–24 in the specification).
  static const double sectionGap = 24;
}

/// Corner radii, on the Material 3 Expressive scale. Buttons, segments and
/// tiles are pills: half of their height.
abstract final class AppRadii {
  /// Bars, chips and small elements.
  static const double small = 8;

  static const double textField = 12;

  static const double fab = 16;

  /// Elements inside a card.
  static const double inner = 20;

  /// Choice rows, such as the palette rows.
  static const double choiceRow = 24;

  /// Cards, notices and groups of entries.
  static const double card = 28;

  /// Top corners of a bottom sheet.
  static const double sheet = 28;

  /// Hub cards and the house.
  static const double hubCard = 32;
}

/// Sizes of the components.
abstract final class AppSizes {
  /// Smallest touch target, on both axes.
  static const double minTouchTarget = 48;

  /// Height of a compact pill button.
  static const double compactButtonHeight = 44;

  /// Height of a main pill button (52–56 in the specification).
  static const double buttonHeight = 52;

  static const double fab = 56;

  /// Minimum height of a list row (60–64 in the specification).
  static const double listRowMinHeight = 60;

  static const double topBarHeight = 64;

  /// Avatar in the hub.
  static const double hubAvatar = 48;

  /// Avatar in the lists.
  static const double listAvatar = 40;

  /// Icons in the bars and in the entries.
  static const double icon = 24;

  /// Icons inside buttons and tiles.
  static const double iconSmall = 20;

  /// Icons of the house placeholders.
  static const double iconHouse = 18;

  /// Width of the focus ring.
  static const double focusRing = 3;
}

/// Opacities of the component states (section 8).
abstract final class AppOpacities {
  /// State layer of a pressed or focused component.
  static const double stateLayer = 0.10;

  /// Content of a disabled component, over `onSurface`.
  static const double disabledContent = 0.38;

  /// Container of a disabled component, over `onSurface`.
  static const double disabledContainer = 0.12;
}
