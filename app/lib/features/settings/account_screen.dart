import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:homemade/features/auth/delete_demo_account.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Account (I2), provisional: the placeholder with the "Esci" button and
/// nothing about the user. "Esci" asks to confirm, then the router goes to
/// sign-in (A2). A demo account also has "Elimina account demo"
/// (`docs/spec/accesso.md`, section 12).
class AccountScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _deleting = false;

  /// Asks to confirm, then deletes the demo account. The router leaves this
  /// screen when it is done; a failure is a snackbar.
  Future<void> _deleteDemoAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDemoAccountDialog(),
    );
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(startupGateProvider).deleteDemoAccount();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      final message = switch (RemoteFailure.of(error)) {
        RemoteFailure.connection =>
          'Nessuna connessione. Controlla la rete e riprova.',
        RemoteFailure.server =>
          "Non è stato possibile eliminare l'account. Riprova.",
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gate = ref.watch(startupGateProvider);
    final errorStyle = OutlinedButton.styleFrom(foregroundColor: scheme.error);
    return Scaffold(
      appBar: AppBar(title: Text(screenByCode('I2').label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PlaceholderMark(),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    style: errorStyle,
                    onPressed: _deleting
                        ? null
                        : () => unawaited(confirmSignOut(context, ref)),
                    child: const Text('Esci'),
                  ),
                  ValueListenableBuilder(
                    valueListenable: gate,
                    builder: (context, _, _) => !gate.isDemo
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: OutlinedButton(
                              style: errorStyle,
                              onPressed: _deleting
                                  ? null
                                  : () => unawaited(_deleteDemoAccount()),
                              child: _deleting
                                  ? const SizedBox.square(
                                      dimension: AppSizes.iconSmall,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(deleteDemoAccountLabel),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
