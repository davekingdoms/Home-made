import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';

/// A configuration with every value set, except the ones given.
AppConfig _config({
  String appEnv = 'dev',
  String supabaseUrl = 'placeholder',
  String supabasePublishableKey = 'placeholder',
  String googleWebClientId = 'placeholder',
  String pagesBaseUrl = 'placeholder',
}) => AppConfig(
  appEnv: appEnv,
  supabaseUrl: supabaseUrl,
  supabasePublishableKey: supabasePublishableKey,
  googleWebClientId: googleWebClientId,
  pagesBaseUrl: pagesBaseUrl,
);

void main() {
  test('lists the names of the required keys without a value', () {
    final config = _config(supabaseUrl: '', googleWebClientId: '');

    expect(config.missingKeys, ['SUPABASE_URL', 'GOOGLE_WEB_CLIENT_ID']);
  });

  test('requires the Supabase, Google and Pages keys', () {
    final config = _config(
      supabaseUrl: '',
      supabasePublishableKey: '',
      googleWebClientId: '',
      pagesBaseUrl: '',
    );

    expect(config.missingKeys, [
      'SUPABASE_URL',
      'SUPABASE_PUBLISHABLE_KEY',
      'GOOGLE_WEB_CLIENT_ID',
      'PAGES_BASE_URL',
    ]);
  });

  test('has no missing key when every required value is set', () {
    expect(_config().missingKeys, isEmpty);
  });

  test('APP_ENV is optional', () {
    expect(_config(appEnv: '').missingKeys, isEmpty);
  });

  test('is dev only when APP_ENV is exactly dev', () {
    expect(_config().isDev, isTrue);
    for (final appEnv in ['', 'prod', 'test', 'Dev', 'dev ', ' dev']) {
      expect(_config(appEnv: appEnv).isDev, isFalse, reason: appEnv);
    }
  });

  test('builds the address of a page of the Pages site', () {
    final config = _config(pagesBaseUrl: 'https://example.pages.dev');

    expect(
      config.pagesUri('/privacy/'),
      Uri.parse('https://example.pages.dev/privacy/'),
    );
  });

  test('the keys match env.example.json', () {
    final example = jsonDecode(
      File('env.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(AppConfig.keys, example.keys);
  });
}
