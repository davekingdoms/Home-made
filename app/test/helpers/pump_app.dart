import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/app.dart';
import 'package:homemade/core/router/app_router.dart';
import 'package:homemade/features/auth/auth_repository.dart';

import 'fake_auth_repository.dart';

/// Pumps the whole app, started at [location], and returns its router.
///
/// [auth] defaults to a fake repository with an open session.
Future<GoRouter> pumpApp(
  WidgetTester tester, {
  String location = '/',
  AuthRepository? auth,
}) async {
  final repository = auth ?? FakeAuthRepository();
  final router = buildAppRouter(auth: repository, initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        appRouterProvider.overrideWithValue(router),
      ],
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
