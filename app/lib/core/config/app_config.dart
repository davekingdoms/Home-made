import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_config.g.dart';

/// Build-time configuration, read from `--dart-define-from-file`.
///
/// The keys are listed in `env.example.json`. Values are public by nature but
/// stay out of the repository, and are never written to logs.
///
/// The app does not start without the Supabase URL, the Supabase publishable
/// key, the Google web client ID and the address of Pages: `main` shows the
/// names of the missing ones instead. `APP_ENV` is optional.
class AppConfig {
  const new({
    required this.appEnv,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
    required this.pagesBaseUrl,
  });

  /// The configuration compiled into this build.
  static const fromEnvironment = AppConfig(
    appEnv: String.fromEnvironment(appEnvKey),
    supabaseUrl: String.fromEnvironment(supabaseUrlKey),
    supabasePublishableKey: String.fromEnvironment(supabasePublishableKeyKey),
    googleWebClientId: String.fromEnvironment(googleWebClientIdKey),
    pagesBaseUrl: String.fromEnvironment(pagesBaseUrlKey),
  );

  static const appEnvKey = 'APP_ENV';
  static const supabaseUrlKey = 'SUPABASE_URL';
  static const supabasePublishableKeyKey = 'SUPABASE_PUBLISHABLE_KEY';
  static const googleWebClientIdKey = 'GOOGLE_WEB_CLIENT_ID';
  static const pagesBaseUrlKey = 'PAGES_BASE_URL';

  /// Every key, in the order of `env.example.json`.
  static const List<String> keys = [
    appEnvKey,
    supabaseUrlKey,
    supabasePublishableKeyKey,
    googleWebClientIdKey,
    pagesBaseUrlKey,
  ];

  /// Optional: the name of the environment the build points to.
  final String appEnv;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;

  /// Stable address of the Cloudflare Pages site, without the final `/`:
  /// the pages the app links to, such as the privacy notice, are under it.
  final String pagesBaseUrl;

  /// Names (never values) of the required keys this build has no value for.
  ///
  /// The app starts only when the list is empty.
  List<String> get missingKeys => [
    if (supabaseUrl.isEmpty) supabaseUrlKey,
    if (supabasePublishableKey.isEmpty) supabasePublishableKeyKey,
    if (googleWebClientId.isEmpty) googleWebClientIdKey,
    if (pagesBaseUrl.isEmpty) pagesBaseUrlKey,
  ];

  /// The page [path] of the Pages site, such as `/privacy/`.
  Uri pagesUri(String path) => Uri.parse('$pagesBaseUrl$path');
}

/// The configuration of this build; tests override it.
@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => AppConfig.fromEnvironment;
