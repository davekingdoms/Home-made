import 'package:go_router/go_router.dart';
import 'package:homemade/features/auth/auth_routes.dart';
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
/// always ends there. The session check arrives with the sign-in.
GoRouter buildAppRouter({String initialLocation = '/'}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
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
        ],
      ),
    ],
  );
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = buildAppRouter();
  ref.onDispose(router.dispose);
  return router;
}
