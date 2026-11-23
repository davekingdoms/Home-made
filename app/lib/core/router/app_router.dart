import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/startup_redirect.dart';
import 'package:homemade/features/auth/auth_routes.dart';
import 'package:homemade/features/dev/component_catalog_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/finance/finance_shell.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/household/household_routes.dart';
import 'package:homemade/features/hub/hub_screen.dart';
import 'package:homemade/features/location/location_routes.dart';
import 'package:homemade/features/settings/settings_routes.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/features/startup/startup_screen.dart';
import 'package:homemade/features/startup/startup_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// The router of the app, with the routes of `docs/spec/navigazione.md`.
///
/// The hub is the entry screen and the parent of the sections, so that back
/// always ends there.
///
/// The redirect reads only [startup], the state of the startup gate, and
/// runs again whenever it changes: while a step is missing every path leads
/// to its screen, then to the screen asked for ([startupRedirect]).
GoRouter buildAppRouter({
  required ValueListenable<StartupState> startup,
  String initialLocation = '/',
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: startup,
    redirect: (context, state) => startupRedirect(startup.value, state.uri),
    routes: [
      startupRoute(),
      ...authRoutes(),
      householdRoute(),
      locationRoute(),
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
  final router = buildAppRouter(startup: ref.watch(startupGateProvider));
  ref.onDispose(router.dispose);
  return router;
}
