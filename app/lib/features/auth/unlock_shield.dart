import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/router/app_router.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/auth/unlock_screen.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/motion.dart';
import 'package:material_ui/material_ui.dart';

/// Covers the app ([child], the router) with the unlock (A1) while the
/// startup gate is locked (`docs/spec/accesso.md`, section 2).
///
/// A1 is not a route: the screens under it stay as they are (tab, details,
/// sheets, text written) and come back after the unlock. While A1 shows,
/// the app under it gets no touches, no focus (the keyboard closes) and is
/// hidden from the screen reader; the system back does what it does from
/// the hub, it leaves the app, and never reaches the screens under A1. A1
/// has a navigator of its own, for the confirmation of "Esci".
///
/// A1 appears at once, with no frame of the app before it, and fades out.
class UnlockShield extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UnlockShield> createState() => _UnlockShieldState();
}

class _UnlockShieldState extends ConsumerState<UnlockShield>
    with SingleTickerProviderStateMixin {
  late final StartupGate _gate;

  /// Opacity of A1: 1 while locked, down to 0 after the unlock.
  late final AnimationController _opacity;

  final _navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'unlock');
  final GlobalKey _appKey = GlobalKey(debugLabel: 'app');

  bool _locked = false;

  /// Takes the system back before the router while locked.
  ChildBackButtonDispatcher? _back;

  /// Whether the navigators of the app can go back, as they last said: the
  /// system back goes to the app again once A1 goes.
  bool _appCanPop = false;

  @override
  void initState() {
    super.initState();
    _opacity = AnimationController(vsync: this, duration: AppDurations.medium)
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) setState(() {});
      });
    _gate = ref.read(startupGateProvider)..addListener(_onGateChanged);
    _locked = _gate.value.locked;
    if (_locked) _cover();
  }

  @override
  void dispose() {
    _gate.removeListener(_onGateChanged);
    _releaseBack();
    _opacity.dispose();
    super.dispose();
  }

  void _onGateChanged() {
    final locked = _gate.value.locked;
    if (locked == _locked) return;
    setState(() => _locked = locked);
    if (locked) {
      _cover();
    } else {
      _releaseBack();
      _setFrameworkHandlesBack(_appCanPop);
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _opacity.value = 0;
      } else {
        _opacity.animateBack(0, curve: AppCurves.exit);
      }
    }
  }

  /// A1 at once, with the system back.
  void _cover() {
    _opacity.value = 1;
    _takeBack();
    _setFrameworkHandlesBack(false);
  }

  void _takeBack() {
    final router = ref.read(appRouterProvider);
    _back = ChildBackButtonDispatcher(router.backButtonDispatcher)
      ..addCallback(_onBack)
      ..takePriority();
  }

  void _releaseBack() {
    _back?.removeCallback(_onBack);
    _back = null;
  }

  /// The system back with A1 on screen: it closes the confirmation of
  /// "Esci", if open; otherwise the app leaves, as from the hub.
  Future<bool> _onBack() async {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && await navigator.maybePop()) return true;
    await SystemNavigator.pop();
    return true;
  }

  /// Tells Android whether the app handles the back gesture, as the app does
  /// for its navigators: with A1 and no dialog the system handles it, and
  /// the app leaves.
  void _setFrameworkHandlesBack(bool handles) {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.detached) return;
    unawaited(SystemNavigator.setFrameworkHandlesBack(handles));
  }

  @override
  Widget build(BuildContext context) {
    final covered = _locked || !_opacity.isDismissed;
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(
          key: _appKey,
          child: NotificationListener<NavigationNotification>(
            onNotification: (notification) {
              _appCanPop = notification.canHandlePop;
              // While locked the app says nothing about the back.
              return _locked;
            },
            child: ExcludeFocus(
              excluding: _locked,
              child: ExcludeSemantics(
                excluding: _locked,
                child: IgnorePointer(ignoring: _locked, child: widget.child),
              ),
            ),
          ),
        ),
        if (covered)
          ExcludeFocus(
            excluding: !_locked,
            child: ExcludeSemantics(
              excluding: !_locked,
              child: IgnorePointer(
                ignoring: !_locked,
                child: FadeTransition(
                  opacity: _opacity,
                  child: NotificationListener<NavigationNotification>(
                    onNotification: (notification) {
                      if (_locked) {
                        _setFrameworkHandlesBack(notification.canHandlePop);
                      }
                      return true;
                    },
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: _navigatorKey,
                        onGenerateRoute: (settings) => PageRouteBuilder<void>(
                          settings: settings,
                          transitionDuration: Duration.zero,
                          pageBuilder: (context, _, _) => const _LockedScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A1 over the app: "Sblocca" asks the gate, "Esci dall'account" confirms
/// and leaves the account (A2, without a message).
class _LockedScreen extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(startupGateProvider);
    return ValueListenableBuilder(
      valueListenable: gate.unlocking,
      builder: (context, unlocking, _) => UnlockScreen(
        unlocking: unlocking,
        onUnlock: () => unawaited(gate.unlock()),
        onSignOut: () => unawaited(confirmSignOut(context, ref)),
      ),
    );
  }
}
