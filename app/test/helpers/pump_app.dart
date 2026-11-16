import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/app.dart';
import 'package:homemade/core/router/app_router.dart';

/// Pumps the whole app, started at [location], and returns its router.
Future<GoRouter> pumpApp(WidgetTester tester, {String location = '/'}) async {
  final router = buildAppRouter(initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appRouterProvider.overrideWithValue(router)],
      child: const HomemadeApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Presses the system back button.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

extension RouterLocation on GoRouter {
  /// The path the router currently shows.
  String get location => routerDelegate.currentConfiguration.uri.path;
}
