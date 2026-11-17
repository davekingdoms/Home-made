import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:material_ui/material_ui.dart';

/// Sign-in (A2), provisional: the "Continua con Google" button and nothing
/// about the user. Layout and texts arrive with the sign-in specification.
class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    final result = await ref.read(authRepositoryProvider).signInWithGoogle();
    // With a session the router leaves this screen: the indicator stays
    // until then.
    if (!mounted || result == SignInResult.signedIn) return;
    setState(() => _signingIn = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == SignInResult.cancelled
                ? 'Accesso annullato'
                : 'Accesso non riuscito. Riprova.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(screenByCode('A2').label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Home-made', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            const PlaceholderMark(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _signingIn ? null : () => unawaited(_signIn()),
              child: _signingIn
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continua con Google'),
            ),
          ],
        ),
      ),
    );
  }
}
