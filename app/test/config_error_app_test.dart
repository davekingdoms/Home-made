import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/config/config_error_app.dart';

void main() {
  const runCommand =
      'fvm flutter run --flavor dev '
      '--dart-define-from-file=../private/env.dev.json';

  testWidgets('shows the names of the missing keys and the run command', (
    tester,
  ) async {
    const config = AppConfig(
      appEnv: '',
      supabaseUrl: '',
      supabasePublishableKey: 'placeholder',
      googleWebClientId: '',
      pagesBaseUrl: 'placeholder',
    );

    await tester.pumpWidget(ConfigErrorApp(missingKeys: config.missingKeys));

    expect(find.text('Configurazione incompleta'), findsOneWidget);
    expect(find.text('SUPABASE_URL'), findsOneWidget);
    expect(find.text('GOOGLE_WEB_CLIENT_ID'), findsOneWidget);
    expect(find.text('SUPABASE_PUBLISHABLE_KEY'), findsNothing);
    expect(find.text('APP_ENV'), findsNothing);
    expect(find.textContaining('non corrisponde'), findsNothing);
    expect(find.text(runCommand), findsOneWidget);
  });

  testWidgets('names the flavor APP_ENV does not match, without values', (
    tester,
  ) async {
    const config = AppConfig(
      appEnv: 'prod',
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'placeholder',
      googleWebClientId: 'placeholder',
      pagesBaseUrl: 'https://example.pages.dev',
    );
    expect(config.matchesFlavor('dev'), isFalse);

    await tester.pumpWidget(
      ConfigErrorApp(missingKeys: config.missingKeys, mismatchedFlavor: 'dev'),
    );

    expect(find.text('Configurazione non valida'), findsOneWidget);
    expect(find.text('APP_ENV non corrisponde al flavor dev'), findsOneWidget);
    expect(find.text('Questa build non ha un valore per:'), findsNothing);
    expect(find.textContaining('prod'), findsNothing);
    expect(find.textContaining('example'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.text(runCommand), findsOneWidget);
  });

  testWidgets('shows both problems together', (tester) async {
    await tester.pumpWidget(
      const ConfigErrorApp(
        missingKeys: ['SUPABASE_URL'],
        mismatchedFlavor: 'prod',
      ),
    );

    expect(find.text('Configurazione incompleta'), findsOneWidget);
    expect(find.text('SUPABASE_URL'), findsOneWidget);
    expect(find.text('APP_ENV non corrisponde al flavor prod'), findsOneWidget);
  });
}
