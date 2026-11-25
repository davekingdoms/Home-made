import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/features/auth/sign_in_screen.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/auth/unlock_screen.dart';
import 'package:homemade/features/auth/welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Unlock (A1), sign-in (A2) and first access (A3).
///
/// A1 is not a step of the router: it covers the app from outside it (the
/// unlock shield). Its path only shows a preview, from the screen index.
List<RouteBase> authRoutes() => [
  GoRoute(path: '/unlock', builder: (context, state) => const UnlockPreview()),
  GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
  GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
];

/// A1 as a screen of the router, for the screen index: "Sblocca" leaves it
/// as an unlock would, "Esci dall'account" leaves the account as in A1.
class UnlockPreview extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => UnlockScreen(
    onUnlock: () => context.canPop() ? context.pop() : context.go('/'),
    onSignOut: () => confirmSignOut(context, ref),
  );
}
