import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/features/startup/startup_state.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Snackbar of the hub after an invite link opened by an account already
/// in a household (`docs/spec/accesso.md`, section 1).
const alreadyInHouseholdMessage =
    'Fai già parte di una casa: un account può stare in una sola casa.';

/// Hub (B1): the entry screen, with one card per section. It tells the
/// notices of the startup once, in a snackbar.
class HubScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _StartupNotices(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Home-made'),
          actions: [
            IconButton(
              tooltip: 'Impostazioni',
              onPressed: () => context.go(screenByCode('I1').location!),
              icon: CircleAvatar(
                backgroundColor: scheme.tertiary,
                foregroundColor: scheme.onTertiary,
                child: const Icon(Symbols.person_rounded),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          // In the centred column until the hub gets its layouts for each
          // window class (PR 4.10).
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      icon: Symbols.account_balance_wallet_rounded,
                      name: 'Finanze',
                      onTap: () => context.go(screenByCode('C1').location!),
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      icon: Symbols.kitchen_rounded,
                      name: 'Dispensa',
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      icon: Symbols.folder_rounded,
                      name: 'Documenti',
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      icon: Symbols.pets_rounded,
                      name: 'Animali',
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go(screenIndexPath),
                        child: const Text('Indice delle schermate'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the notices of the startup gate in a snackbar, once each: now and
/// whenever one comes while the hub is open.
class _StartupNotices extends ConsumerStatefulWidget {
  const new({required this.child});

  final Widget child;

  @override
  ConsumerState<_StartupNotices> createState() => _StartupNoticesState();
}

class _StartupNoticesState extends ConsumerState<_StartupNotices> {
  late final StartupGate _gate = ref.read(startupGateProvider);

  @override
  void initState() {
    super.initState();
    _gate.notice.addListener(_show);
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    _gate.notice.removeListener(_show);
    super.dispose();
  }

  void _show() {
    final notice = _gate.notice.value;
    if (notice == null || !mounted) return;
    _gate.clearNotice();
    final message = switch (notice) {
      StartupNotice.alreadyInHousehold => alreadyInHouseholdMessage,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Section card: active when [onTap] is set, otherwise "In arrivo".
class _SectionCard extends StatelessWidget {
  const new({required this.icon, required this.name, this.onTap});

  final IconData icon;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = onTap != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.hubCard),
    );
    return Card(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: active
                    ? scheme.tertiary
                    : scheme.surfaceContainerHigh,
                foregroundColor: active
                    ? scheme.onTertiary
                    : scheme.onSurfaceVariant,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: active
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (!active)
                      Text(
                        'In arrivo',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appColors.testoTerziario,
                        ),
                      ),
                  ],
                ),
              ),
              if (active)
                Icon(
                  Symbols.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
