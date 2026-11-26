import 'package:homemade/core/config/app_flavor.dart';
import 'package:homemade/theme/app_theme.dart';
import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Shown in place of the app when the configuration of the build is not
/// usable: the names of the required keys without a value, or the flavor that
/// `APP_ENV` does not match, and the command that passes the configuration
/// file. Names only, never values. It has no router.
class ConfigErrorApp extends StatelessWidget {
  const new({required this.missingKeys, this.mismatchedFlavor, super.key});

  /// Command that starts the app with its configuration file.
  static const runCommand =
      'fvm flutter run --flavor dev '
      '--dart-define-from-file=../private/env.dev.json';

  /// Names (never values) of the keys without a value.
  final List<String> missingKeys;

  /// The flavor of the build (`--flavor`) that `APP_ENV` does not match, if
  /// any: see `AppConfig.matchesFlavor`.
  final String? mismatchedFlavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppFlavor.appName(),
      theme: buildAppTheme(AppPalette.teal, Brightness.light),
      darkTheme: buildAppTheme(AppPalette.teal, Brightness.dark),
      home: _ConfigErrorScreen(
        missingKeys: missingKeys,
        mismatchedFlavor: mismatchedFlavor,
      ),
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  const new({required this.missingKeys, required this.mismatchedFlavor});

  final List<String> missingKeys;
  final String? mismatchedFlavor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final flavor = mismatchedFlavor;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          missingKeys.isEmpty
              ? 'Configurazione non valida'
              : 'Configurazione incompleta',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (missingKeys.isNotEmpty) ...[
              Text(
                'Questa build non ha un valore per:',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              for (final key in missingKeys) Text(key, style: code),
              const SizedBox(height: 24),
            ],
            if (flavor != null) ...[
              Text(
                'APP_ENV non corrisponde al flavor $flavor',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
            ],
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
