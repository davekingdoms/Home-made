import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/config/app_flavor.dart';

void main() {
  test('tests run without a flavor', () {
    expect(AppFlavor.current, isNull);
    expect(AppFlavor.appName(), 'Home-made');
  });

  test('the dev build has a name of its own', () {
    expect(AppFlavor.appName('dev'), 'Home-made dev');
    expect(AppFlavor.appName('prod'), 'Home-made');
  });

  test('the names match app_name in build.gradle.kts', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final names = {
      for (final match in RegExp(
        r'create\("(\w+)"\) \{[^}]*resValue\("string", "app_name", "([^"]+)"\)',
      ).allMatches(gradle))
        match[1]: match[2],
    };

    expect(names, {
      'dev': AppFlavor.appName('dev'),
      'prod': AppFlavor.appName('prod'),
    });
  });
}
