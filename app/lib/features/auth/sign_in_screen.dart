import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/design/notice_card.dart';
import 'package:homemade/design/phone_layout.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Text of A2 after an expired or revoked session.
const sessionLostMessage = 'La sessione è scaduta: accedi di nuovo.';

/// The message A2 shows after a sign-in that ended with [result]; null for
/// none.
///
/// `google_sign_in` has no code of its own for a phone without a Google
/// account (on Android it is an `unknownError`, told apart only by its
/// description): that case gets the generic message, and the log only the
/// code.
String? signInMessage(SignInResult result) => switch (result) {
  SignInResult.signedIn || SignInResult.cancelled => null,
  SignInResult.networkError =>
    'Nessuna connessione. Controlla la rete e riprova.',
  SignInResult.configurationError ||
  SignInResult.rejected ||
  SignInResult.failed => 'Accesso non riuscito. Riprova.',
};

/// Text of the checkbox of the demo accounts in A2.
const demoChoiceLabel = 'Modalità demo';

/// Sign-in (A2): logo, name of the app, the "Continua con Google" button,
/// the one way to sign in and to sign up (`docs/spec/accesso.md`,
/// section 3). On `dev` only, the checkbox of the demo accounts
/// (section 12).
class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _signingIn = false;

  /// The choice of "Modalità demo"; null until it is read from the device.
  bool? _demo;

  @override
  void initState() {
    super.initState();
    if (ref.read(appConfigProvider).isDev) unawaited(_readDemoChoice());
  }

  Future<void> _readDemoChoice() async {
    final chosen = await ref.read(startupGateProvider).demoChosen();
    // A tap that came first wins.
    if (mounted && _demo == null) setState(() => _demo = chosen);
  }

  void _chooseDemo(bool demo) {
    setState(() => _demo = demo);
    unawaited(ref.read(startupGateProvider).chooseDemo(demo: demo));
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    final result = await ref.read(authRepositoryProvider).signInWithGoogle();
    // With a session the router leaves this screen: the indicator stays
    // until then.
    if (!mounted || result == SignInResult.signedIn) return;
    setState(() => _signingIn = false);
    final message = signInMessage(result);
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gate = ref.watch(startupGateProvider);
    return Scaffold(
      body: SafeArea(
        child: PhoneLayout(
          centered: true,
          children: [
            const Center(child: AppLogo()),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Home-made',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Conti, spese e conguagli di casa in un posto solo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            ValueListenableBuilder(
              valueListenable: gate,
              builder: (context, state, _) => !state.sessionLost
                  ? const SizedBox.shrink()
                  : const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: NoticeCard(
                        kind: NoticeKind.info,
                        title: sessionLostMessage,
                      ),
                    ),
            ),
            FilledButton(
              onPressed: _signingIn ? null : () => unawaited(_signIn()),
              child: _signingIn
                  ? const SizedBox.square(
                      dimension: AppSizes.iconSmall,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continua con Google'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Accedi o registrati con il tuo account Google.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (ref.watch(appConfigProvider).isDev) ...[
              const SizedBox(height: AppSpacing.md),
              _DemoCheckbox(
                value: _demo ?? false,
                enabled: !_signingIn,
                onChanged: _chooseDemo,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Modalità demo": the box and the text toggle it.
class _DemoCheckbox extends StatelessWidget {
  const new({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          semanticLabel: demoChoiceLabel,
          onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        ),
        GestureDetector(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Text(
            demoChoiceLabel,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
