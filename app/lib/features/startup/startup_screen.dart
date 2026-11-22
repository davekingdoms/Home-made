import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/design/app_logo.dart';
import 'package:homemade/design/phone_layout.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/features/startup/startup_state.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_ui/material_ui.dart';

/// Path of the startup screen. It is not a screen of the inventory: the
/// router shows it while the startup state is not known.
const startupPath = '/start';

RouteBase startupRoute() => GoRoute(
  path: startupPath,
  builder: (context, state) => const StartupScreen(),
);

/// While the startup gate reads the account: the logo alone, so that no
/// other screen shows for an instant. When the account cannot be read and
/// nothing is saved on the device: what happened and "Riprova".
class StartupScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(startupGateProvider);
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: gate,
          builder: (context, state, _) {
            final failure = state.failure;
            if (state.step != StartupStep.unavailable || failure == null) {
              return const Center(child: AppLogo(semanticLabel: 'Home-made'));
            }
            return _Unavailable(failure: failure, onRetry: gate.retry);
          },
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const new({required this.failure, required this.onRetry});

  final RemoteFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhoneLayout(
      centered: true,
      children: [
        Text(
          switch (failure) {
            RemoteFailure.connection =>
              'Nessuna connessione. Controlla la rete e riprova.',
            RemoteFailure.server =>
              'Non è stato possibile caricare i dati. Riprova.',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ),
      ],
    );
  }
}
