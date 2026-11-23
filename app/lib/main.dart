import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:homemade/app.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/config/config_error_app.dart';
import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/supabase_auth_repository.dart';
import 'package:homemade/features/device/device_repository.dart';
import 'package:homemade/features/device/supabase_device_repository.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/supabase_account_repository.dart';
import 'package:homemade/theme/font_license.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicense();

  const config = AppConfig.fromEnvironment;
  final missingKeys = config.missingKeys;
  if (missingKeys.isNotEmpty) {
    runApp(ConfigErrorApp(missingKeys: missingKeys));
    return;
  }

  final supabase = await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
    // Supabase prints its own log in debug builds: it stays off, so that
    // nothing about the session reaches the console.
    debug: false,
  );
  final auth = await SupabaseAuthRepository.start(
    auth: supabase.client.auth,
    googleSignIn: GoogleSignIn.instance,
    serverClientId: config.googleWebClientId,
  );

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(
          SupabaseAccountRepository(supabase.client),
        ),
        deviceRepositoryProvider.overrideWithValue(
          SupabaseDeviceRepository(supabase.client),
        ),
        localStoreProvider.overrideWithValue(SharedPreferencesLocalStore()),
      ],
      child: const HomemadeApp(),
    ),
  );
}
