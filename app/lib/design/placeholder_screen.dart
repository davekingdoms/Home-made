import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:material_ui/material_ui.dart';

/// Stand-in for a screen that is not specified and built yet: its code and
/// name, the word "Segnaposto" and a button for each screen and sheet
/// reachable from it.
class PlaceholderScreen extends StatelessWidget {
  const new({required this.entry, this.embedded = false, super.key});

  final ScreenEntry entry;

  /// True inside a section shell, which already provides the top bar: the
  /// title moves to the body.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (embedded) ...[
          Text(entry.label, style: theme.textTheme.headlineLarge),
          const SizedBox(height: 8),
        ],
        const PlaceholderMark(),
        const SizedBox(height: 24),
        PlaceholderLinks(entry: entry),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(entry.label)),
      body: SafeArea(child: body),
    );
  }
}

/// The word "Segnaposto".
class PlaceholderMark extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Segnaposto',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One button for each screen and sheet reachable from [entry].
class PlaceholderLinks extends StatelessWidget {
  const new({required this.entry, this.closeBeforeOpening = false, super.key});

  final ScreenEntry entry;

  /// True inside a bottom sheet, which closes before opening its target.
  final bool closeBeforeOpening;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final target in entry.opens.map(screenByCode))
          if (target.isSheet)
            FilledButton.tonal(
              key: ValueKey('open-${target.code}'),
              onPressed: () => _open(context, target),
              child: Text(target.label),
            )
          else
            for (final example in target.exampleLocations.entries)
              FilledButton.tonal(
                key: ValueKey('open-${target.code}-${example.key}'),
                onPressed: () => _open(context, target, example.key),
                child: Text(example.value),
              ),
      ],
    );
  }

  void _open(BuildContext context, ScreenEntry target, [String? location]) {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    if (closeBeforeOpening) navigator.pop();
    openScreenEntry(navigator.context, router, target, location: location);
  }
}

/// Opens [target]: a bottom sheet, a route pushed on top of the current
/// screen, or a route with its section underneath.
void openScreenEntry(
  BuildContext context,
  GoRouter router,
  ScreenEntry target, {
  String? location,
}) {
  if (target.isSheet) {
    unawaited(showPlaceholderSheet(context, target));
    return;
  }
  final destination = location ?? target.location!;
  if (target.opensOnTop) {
    unawaited(router.push<void>(destination));
  } else {
    router.go(destination);
  }
}

/// Shows the placeholder of the bottom sheet [entry] above everything else.
Future<void> showPlaceholderSheet(BuildContext context, ScreenEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(entry.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const PlaceholderMark(),
            const SizedBox(height: 24),
            PlaceholderLinks(entry: entry, closeBeforeOpening: true),
          ],
        ),
      ),
    ),
  );
}
