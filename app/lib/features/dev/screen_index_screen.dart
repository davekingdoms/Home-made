import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Path of the screen index. Temporary: it goes away when every screen is
/// built (section 4 of `docs/spec/navigazione.md`).
const screenIndexPath = '/dev/screens';

RouteBase screenIndexRoute() => GoRoute(
  path: 'dev/screens',
  builder: (context, state) => const ScreenIndexScreen(),
);

/// Development list of every screen and sheet, to open them directly.
class ScreenIndexScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Indice delle schermate')),
      body: SafeArea(
        child: ListView(
          children: [
            for (final level in ScreenLevel.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  level.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final entry in screenCatalog.where((e) => e.level == level))
                ListTile(
                  key: ValueKey('index-${entry.code}'),
                  leading: SizedBox(
                    width: 40,
                    child: Text(entry.code, style: theme.textTheme.labelLarge),
                  ),
                  title: Text(entry.title),
                  subtitle: entry.path == null ? null : Text(entry.path!),
                  onTap: () =>
                      openScreenEntry(context, GoRouter.of(context), entry),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
