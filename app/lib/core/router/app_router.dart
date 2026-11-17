import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/auth_routes.dart';
import 'package:homemade/features/dev/component_catalog_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/finance/finance_shell.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/household/household_routes.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/settings/settings_routes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// The router of the app, with the routes of `docs/spec/navigazione.md`.
///
/// The hub is the entry screen and the parent of the sections, so that back
/// always ends there.
///
/// The session of [auth] is checked at startup and whenever it changes:
/// without a session every path leads to sign-in (A2), with a session sign-in
/// leads to the hub. Unlock (A1) and first access (A3, A7–A10) are not
/// connected yet.
GoRouter buildAppRouter({
  required AuthRepository auth,
  String initialLocation = '/',
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final signInPath = screenByCode('A2').path!;
  final hubPath = screenByCode('B1').path!;
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: auth.hasSession,
    redirect: (context, state) {
      final atSignIn = state.matchedLocation == signInPath;
      if (!auth.hasSession.value) return atSignIn ? null : signInPath;
      return atSignIn ? hubPath : null;
    },
    routes: [
      ...authRoutes(),
      householdRoute(),
      GoRoute(
        path: '/',
        builder: (context, state) => const HubScreen(),
        routes: [
          financeRoute(rootKey),
          manualEntryRoute(rootKey),
          settingsRoute(),
          screenIndexRoute(),
          componentCatalogRoute(),
        ],
      ),
    ],
  );
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = buildAppRouter(auth: ref.watch(authRepositoryProvider));
  ref.onDispose(router.dispose);
  return router;
}
