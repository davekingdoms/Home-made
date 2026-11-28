import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/startup_redirect.dart';
import 'package:homemade/features/auth/auth_routes.dart';
import 'package:homemade/features/dev/component_catalog_screen.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/finance/finance_shell.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/household/household_routes.dart';
import 'package:homemade/features/household/invite_link.dart';
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
/// runs again whenever its step changes: while a step is missing every path
/// leads to its screen, then to the screen asked for ([startupRedirect]).
/// The lock is not a step: the unlock (A1) covers the app from outside the
/// router, which does not move when it comes or goes.
///
/// An invite link of [inviteLinks] comes before every other check: it goes
/// to [onInviteLink] when it is valid (only `invite_link_invalid` in the log
/// otherwise), then the router goes on as if the entry screen had been
/// asked. The link is never shown, nor a destination.
GoRouter buildAppRouter({
  required ValueListenable<StartupState> startup,
  InviteLinks? inviteLinks,
  void Function(InviteLinkData link)? onInviteLink,
  String initialLocation = '/',
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: _StepChanges(startup),
    redirect: (context, state) {
      final location = state.uri;
      if (inviteLinks != null && inviteLinks.matches(location)) {
        final link = inviteLinks.read(location);
        if (link == null) {
          developer.log('invite_link_invalid', name: 'household');
        } else {
          onInviteLink?.call(link);
        }
        return startupRedirect(startup.value, Uri(path: '/')) ?? '/';
      }
      return startupRedirect(startup.value, location);
    },
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
  final gate = ref.watch(startupGateProvider);
  final router = buildAppRouter(
    startup: gate,
    inviteLinks: ref.watch(inviteLinksProvider),
    onInviteLink: gate.receiveInvite,
  );
  ref.onDispose(router.dispose);
  return router;
}

/// Notifies when the startup state changes apart from the lock.
class _StepChanges implements Listenable {
  new(this._startup);

  final ValueListenable<StartupState> _startup;

  /// The listener given to [_startup] for each listener of the router.
  final _forwarders = <VoidCallback, VoidCallback>{};

  @override
  void addListener(VoidCallback listener) {
    var last = _unlocked;
    void forward() {
      final current = _unlocked;
      if (current == last) return;
      last = current;
      listener();
    }

    _forwarders[listener] = forward;
    _startup.addListener(forward);
  }

  @override
  void removeListener(VoidCallback listener) {
    final forward = _forwarders.remove(listener);
    if (forward != null) _startup.removeListener(forward);
  }

  StartupState get _unlocked => _startup.value.withLock(locked: false);
}
