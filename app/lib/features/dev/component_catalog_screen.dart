import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/palette_radio_tile.dart';
import 'package:homemade/features/dev/component_catalog.dart';
import 'package:homemade/theme/appearance.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:homemade/theme/motion.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

RouteBase componentCatalogRoute() => GoRoute(
  path: 'dev/components',
  builder: (context, state) => const ComponentCatalogScreen(),
);

/// Development catalog of the components of section 8 of
/// `docs/spec/stile.md`, to look at them on the phone (section 4 of
/// `docs/spec/navigazione.md`).
///
/// Palette and theme change the whole app; the text size changes the
/// components shown here.
class ComponentCatalogScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Text sizes to try: the default, the limit of the hub and the limit of
  /// the other screens.
  static const List<double> textScales = [1, 1.3, 2];

  @override
  ConsumerState<ComponentCatalogScreen> createState() =>
      _ComponentCatalogScreenState();
}

class _ComponentCatalogScreenState
    extends ConsumerState<ComponentCatalogScreen> {
  double _textScale = ComponentCatalogScreen.textScales.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceControllerProvider);
    final controller = ref.read(appearanceControllerProvider.notifier);
    final entry = screenByCode(componentCatalogCode);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sectionGap,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(entry.title)),
      body: SafeArea(
        // Pull down to see the refresh indicator; nothing is reloaded.
        child: RefreshIndicator(
          onRefresh: () => Future<void>.delayed(AppDurations.long),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenMargin,
              0,
              AppSpacing.screenMargin,
              AppSpacing.xxl,
            ),
            children: [
              heading('Palette'),
              RadioGroup<AppPalette>(
                groupValue: appearance.palette,
                onChanged: (palette) {
                  if (palette != null) controller.choosePalette(palette);
                },
                child: Column(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final palette in AppPalette.values)
                      PaletteRadioTile(
                        key: ValueKey('palette-${palette.name}'),
                        palette: palette,
                      ),
                  ],
                ),
              ),
              heading('Tema'),
              SegmentedButton<ThemeMode>(
                key: const ValueKey('theme-mode'),
                segments: [
                  for (final mode in ThemeMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {appearance.themeMode},
                onSelectionChanged: (selection) =>
                    controller.chooseThemeMode(selection.single),
              ),
              heading('Testo'),
              SegmentedButton<double>(
                key: const ValueKey('text-scale'),
                segments: [
                  for (final scale in ComponentCatalogScreen.textScales)
                    ButtonSegment(
                      value: scale,
                      label: Text('${(scale * 100).round()}%'),
                    ),
                ],
                selected: {_textScale},
                onSelectionChanged: (selection) =>
                    setState(() => _textScale = selection.single),
              ),
              for (final component in componentCatalog) ...[
                heading(component.title),
                MediaQuery(
                  key: ValueKey('component-${component.id}'),
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(_textScale)),
                  // The component chooses its own size, up to the width.
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    heightFactor: 1,
                    child: Builder(builder: component.builder),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
