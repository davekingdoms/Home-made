import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Shown in place of the app when the build has no value for a required
/// configuration key: the names of the missing keys and the command that
/// passes the configuration file. It has no router.
class ConfigErrorApp extends StatelessWidget {
  const new({required this.missingKeys, super.key});

  /// Command that starts the app with its configuration file.
  static const runCommand =
      'fvm flutter run --dart-define-from-file=../private/env.dev.json';

  /// Names (never values) of the keys without a value.
  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home-made',
      theme: buildAppTheme(AppPalette.teal, Brightness.light),
      darkTheme: buildAppTheme(AppPalette.teal, Brightness.dark),
      home: _ConfigErrorScreen(missingKeys: missingKeys),
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  const new({required this.missingKeys});

  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(title: const Text('Configurazione incompleta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Questa build non ha un valore per:',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            for (final key in missingKeys) Text(key, style: code),
            const SizedBox(height: 24),
            Text(
              "Avvia l'app con il file di configurazione:",
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(ConfigErrorApp.runCommand, style: code),
          ],
        ),
      ),
    );
  }
}
