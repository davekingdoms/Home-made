import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:material_ui/material_ui.dart';

/// Asks to confirm "Esci" and, if the user confirms, leaves the account:
/// the row of this device and its local id go, then the session. Sign-in
/// (A2) follows, without the message of the expired session.
///
/// The one way out of the account: Account (I2), the menu of first access
/// (A3), unlock (A1) and, from the next iterations, household (A7).
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final gate = ref.read(startupGateProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const SignOutDialog(),
  );
  if (confirmed ?? false) await gate.signOut();
}

/// The confirmation of "Esci": it pops `true` to sign out.
class SignOutDialog extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text("Uscire dall'account?"),
      content: const Text('Per rientrare ti servirà il tuo account Google.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Esci'),
        ),
      ],
    );
  }
}
