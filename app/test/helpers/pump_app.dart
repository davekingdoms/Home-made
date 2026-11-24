import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/app.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/links/link_opener.dart';
import 'package:homemade/core/router/app_router.dart';
import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/device/device_repository.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_repository.dart';
import 'fakes.dart';

/// Configuration of the tests, with invented addresses.
const testConfig = AppConfig(
  appEnv: 'test',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'placeholder',
  googleWebClientId: 'placeholder.apps.googleusercontent.com',
  pagesBaseUrl: 'https://example.pages.dev',
);

/// Window of a phone, in dp: a compact window.
const phoneWindow = Size(400, 800);

/// Makes the window of the test [size] dp, until the end of the test.
void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Gives every test of the enclosing group, or file, the window of a
/// phone; without it the window of the tests is 800 × 600 dp, a medium one.
void usePhoneWindow() {
  final view = TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .implicitView!;
  setUp(() => view.physicalSize = phoneWindow * view.devicePixelRatio);
  tearDown(view.resetPhysicalSize);
}

/// Pumps the whole app, started at [location], and returns its router.
///
/// Every dependency is a fake: [auth] defaults to an open session, and
/// [accounts] to an account that has done every step. [openedLinks]
/// collects the pages the app opens in the browser. [config] defaults to
/// [testConfig], whose `APP_ENV` is not `dev`. [window] sets the size of the
/// window, in dp.
Future<GoRouter> pumpApp(
  WidgetTester tester, {
  String location = '/',
  AppConfig config = testConfig,
  AuthRepository? auth,
  AccountRepository? accounts,
  DeviceRepository? devices,
  LocalStore? store,
  List<Uri>? openedLinks,
  Size? window,
}) async {
  if (window != null) setWindow(tester, window);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      accountRepositoryProvider.overrideWithValue(
        accounts ?? FakeAccountRepository(),
      ),
      deviceRepositoryProvider.overrideWithValue(
        devices ?? FakeDeviceRepository(),
      ),
      localStoreProvider.overrideWithValue(store ?? MemoryLocalStore()),
      linkOpenerProvider.overrideWithValue(
        (uri) async => openedLinks?.add(uri),
      ),
      appRouterProvider.overrideWith((ref) {
        final router = buildAppRouter(
          startup: ref.watch(startupGateProvider),
          initialLocation: location,
        );
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const HomemadeApp()),
  );
  await tester.pumpAndSettle();
  final router = container.read(appRouterProvider);
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
