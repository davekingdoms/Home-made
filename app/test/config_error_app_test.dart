import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/config/config_error_app.dart';

void main() {
  testWidgets('shows the names of the missing keys and the run command', (
    tester,
  ) async {
    const config = AppConfig(
      appEnv: '',
      supabaseUrl: '',
      supabasePublishableKey: 'placeholder',
      googleWebClientId: '',
    );

    await tester.pumpWidget(ConfigErrorApp(missingKeys: config.missingKeys));

    expect(find.text('Configurazione incompleta'), findsOneWidget);
    expect(find.text('SUPABASE_URL'), findsOneWidget);
    expect(find.text('GOOGLE_WEB_CLIENT_ID'), findsOneWidget);
    expect(find.text('SUPABASE_PUBLISHABLE_KEY'), findsNothing);
    expect(find.text('APP_ENV'), findsNothing);
    expect(
      find.text(
        'fvm flutter run --dart-define-from-file=../private/env.dev.json',
      ),
      findsOneWidget,
    );
  });
}
