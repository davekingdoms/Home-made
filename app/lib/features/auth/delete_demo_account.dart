import 'package:material_ui/material_ui.dart';

/// Text of the button of Account (I2), only for a demo account.
const deleteDemoAccountLabel = 'Elimina account demo';

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
