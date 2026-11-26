import 'package:flutter/services.dart';

/// Android product flavors of the build (`--flavor`), defined in
/// `android/app/build.gradle.kts`: `dev`, package `….homemade.dev`, and
/// `prod`, the real app.
abstract final class AppFlavor {
  /// The flavor of the development environment.
  static const dev = 'dev';

  /// The flavor of this build: null without `--flavor`, as in `flutter test`.
  static const String? current = appFlavor;

  /// Name of the app in a build of [flavor].
  ///
  /// The same as `app_name` in `build.gradle.kts`, under the launcher icon:
  /// the title of `MaterialApp` gives it to the app switcher too.
  static String appName([String? flavor = current]) =>
      flavor == dev ? 'Home-made dev' : 'Home-made';
}
