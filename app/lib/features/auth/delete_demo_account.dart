import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:material_ui/material_ui.dart';

/// Text of the button of Account (I2) and of the entry of the menu of A7,
/// only for a demo account.
const deleteDemoAccountLabel = 'Elimina account demo';

/// "Elimina account demo" (`docs/spec/accesso.md`, section 12), from
/// Account (I2) or from the menu of A7: asks to confirm, then deletes the
/// demo account. The router leaves the screen when it is done, for sign-in
/// (A2) without a message.
///
/// [onDeleting] says when the deletion starts (true) and when it failed
/// (false), for the indicator of the screen; a failure is a snackbar.
Future<void> confirmDeleteDemoAccount(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<bool> onDeleting,
}) async {
  final gate = ref.read(startupGateProvider);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const DeleteDemoAccountDialog(),
  );
  if (!(confirmed ?? false) || !context.mounted) return;
  onDeleting(true);
  try {
    await gate.deleteDemoAccount();
  } on Object catch (error) {
    if (!context.mounted) return;
    onDeleting(false);
    final message = switch (RemoteFailure.of(error)) {
      RemoteFailure.connection =>
        'Nessuna connessione. Controlla la rete e riprova.',
      RemoteFailure.server =>
        "Non è stato possibile eliminare l'account. Riprova.",
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The confirmation of "Elimina account demo" (`docs/spec/accesso.md`,
/// section 12): it pops `true` to delete.
class DeleteDemoAccountDialog extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text("Eliminare l'account demo?"),
      content: const Text(
        "Si cancellano l'account, le case rimaste senza altri membri e tutti "
        'i loro dati. Non si può annullare.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Elimina'),
        ),
      ],
    );
  }
}
