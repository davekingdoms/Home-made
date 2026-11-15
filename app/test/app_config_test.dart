import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_config.dart';

void main() {
  test('lists the names of the keys without a value', () {
    const config = AppConfig(
      appEnv: 'dev',
      supabaseUrl: '',
      supabasePublishableKey: 'placeholder',
      googleWebClientId: '',
    );

    expect(config.missingKeys, ['SUPABASE_URL', 'GOOGLE_WEB_CLIENT_ID']);
  });

  test('has no missing key when every value is set', () {
    const config = AppConfig(
      appEnv: 'dev',
      supabaseUrl: 'placeholder',
      supabasePublishableKey: 'placeholder',
      googleWebClientId: 'placeholder',
    );

    expect(config.missingKeys, isEmpty);
  });

  test('the keys match env.example.json', () {
    final example = jsonDecode(
      File('env.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(AppConfig.keys, example.keys);
  });
}
