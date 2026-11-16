import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/dev/screen_index_screen.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Hub (B1): the entry screen, with one card per section.
class HubScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              icon: Symbols.account_balance_wallet_rounded,
              name: 'Finanze',
              onTap: () => context.go(screenByCode('C1').location!),
            ),
            const SizedBox(height: 12),
            const _SectionCard(icon: Symbols.kitchen_rounded, name: 'Dispensa'),
            const SizedBox(height: 12),
            const _SectionCard(
              icon: Symbols.folder_rounded,
              name: 'Documenti',
            ),
            const SizedBox(height: 12),
            const _SectionCard(icon: Symbols.pets_rounded, name: 'Animali'),
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
    );
  }
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
