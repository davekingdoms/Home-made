/// Build-time configuration, read from `--dart-define-from-file`.
///
/// The keys are listed in `env.example.json`. Values are public by nature but
/// stay out of the repository, and are never written to logs.
class AppConfig {
  const new({
    required this.appEnv,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
  });

  /// The configuration compiled into this build.
  static const fromEnvironment = AppConfig(
    appEnv: String.fromEnvironment(appEnvKey),
    supabaseUrl: String.fromEnvironment(supabaseUrlKey),
    supabasePublishableKey: String.fromEnvironment(supabasePublishableKeyKey),
    googleWebClientId: String.fromEnvironment(googleWebClientIdKey),
  );

  static const appEnvKey = 'APP_ENV';
  static const supabaseUrlKey = 'SUPABASE_URL';
  static const supabasePublishableKeyKey = 'SUPABASE_PUBLISHABLE_KEY';
  static const googleWebClientIdKey = 'GOOGLE_WEB_CLIENT_ID';

  /// Every key, in the order of `env.example.json`.
  static const List<String> keys = [
    appEnvKey,
    supabaseUrlKey,
    supabasePublishableKeyKey,
    googleWebClientIdKey,
  ];

  final String appEnv;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  /// Names (never values) of the keys this build has no value for.
  ///
  /// No key is required yet: the app starts without a configuration file.
  List<String> get missingKeys => [
    if (appEnv.isEmpty) appEnvKey,
    if (supabaseUrl.isEmpty) supabaseUrlKey,
    if (supabasePublishableKey.isEmpty) supabasePublishableKeyKey,
    if (googleWebClientId.isEmpty) googleWebClientIdKey,
  ];
}
