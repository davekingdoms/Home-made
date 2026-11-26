import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/core/router/startup_redirect.dart';
import 'package:homemade/design/content_column.dart';
import 'package:homemade/design/cookie.dart';
import 'package:homemade/design/highlight_card.dart';
import 'package:homemade/design/pressable.dart';
import 'package:homemade/features/auth/delete_demo_account.dart';
import 'package:homemade/features/auth/sign_out.dart';
import 'package:homemade/features/startup/startup_gate.dart';
import 'package:homemade/theme/app_colors.dart';
import 'package:homemade/theme/dimens.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Phrase under the greeting of A7.
const householdChoicePhrase =
    'Per iniziare crea la tua casa, oppure entra in quella di chi ti ha '
    'invitato.';

/// Title and text of the card that creates a household.
const createCardTitle = 'Crea una casa';
const createCardText =
    'Scegli il nome e da quando tenere i conti. Gli inviti puoi mandarli '
    'anche dopo.';

/// Title and text of the card of the invites.
const joinCardTitle = 'Ho un invito';
const joinCardText =
    'Scrivi il codice che hai ricevuto, oppure apri il link su questo '
    'dispositivo.';

/// Line at the bottom of A7.
const singleMemberLine =
    'Una casa con un solo membro funziona già: gli altri si aggiungono '
    'quando vuoi.';

/// The greeting of A7: "Ciao, " and the first word of [displayName];
/// without a name, "Ciao".
String householdGreeting(String? displayName) {
  final words = (displayName ?? '').trim().split(RegExp(r'\s+'));
  final first = words.first;
  return first.isEmpty ? 'Ciao' : 'Ciao, $first';
}

/// Create or join a household (A7, `docs/spec/accesso.md`, section 5): the
/// greeting, "Crea una casa" (A8) and "Ho un invito" (A10), and the line on
/// a household of one. The menu of the top bar has "Esci dall'account" and,
/// for a demo account, "Elimina account demo".
///
/// The screen asked for, in the parameter `from`, goes on to A8 and A10.
class HouseholdChoiceScreen extends ConsumerStatefulWidget {
  const new({super.key});

  /// Size of the cookie and of the circle of the cards, and of their icons.
  static const double badgeSize = 56;
  static const double badgeIconSize = 28;

  @override
  ConsumerState<HouseholdChoiceScreen> createState() =>
      _HouseholdChoiceScreenState();
}

enum _MenuAction { signOut, deleteDemoAccount }

class _HouseholdChoiceScreenState extends ConsumerState<HouseholdChoiceScreen> {
  bool _deleting = false;

  /// Opens the screen [code], a child of A7, with the screen asked for.
  void _open(String code) {
    final from = GoRouterState.of(context)
        .uri
        .queryParameters[destinationParameter];
    context.go(
      Uri(
        path: screenByCode(code).path,
        queryParameters: from == null ? null : {destinationParameter: from},
      ).toString(),
    );
  }

  void _onMenu(_MenuAction action) {
    switch (action) {
      case _MenuAction.signOut:
        unawaited(confirmSignOut(context, ref));
      case _MenuAction.deleteDemoAccount:
        unawaited(
          confirmDeleteDemoAccount(
            context,
            ref,
            onDeleting: (deleting) => setState(() => _deleting = deleting),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(startupGateProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          if (_deleting)
            const SizedBox.square(
              dimension: AppSizes.minTouchTarget,
              child: Center(
                child: SizedBox.square(
                  dimension: AppSizes.iconSmall,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PopupMenuButton<_MenuAction>(
              icon: const Icon(Symbols.more_vert_rounded),
              onSelected: _onMenu,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _MenuAction.signOut,
                  child: Text("Esci dall'account"),
                ),
                if (gate.isDemo)
                  const PopupMenuItem(
                    value: _MenuAction.deleteDemoAccount,
                    child: Text(deleteDemoAccountLabel),
                  ),
              ],
            ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: gate,
        builder: (context, _, _) => _ChoiceLayout(
          blocks: [
            _Heading(title: householdGreeting(gate.displayName)),
            _CreateCard(onTap: _deleting ? null : () => _open('A8')),
            _JoinCard(onTap: _deleting ? null : () => _open('A10')),
          ],
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              singleMemberLine,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appColors.testoTerziario),
            ),
          ),
        ),
      ),
    );
  }
}

/// Body of A7: [blocks] from just under the top bar, 24 apart, in the
/// centred column; [footer] at the bottom while it fits, otherwise after
/// them. The whole column scrolls, with large text.
class _ChoiceLayout extends StatelessWidget {
  const new({required this.blocks, required this.footer});

  final List<Widget> blocks;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: ContentColumn.sidePadding(
                constraints.maxWidth,
                insets,
              ).copyWith(bottom: AppSpacing.xl + insets.bottom),
              child: ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, block) in blocks.indexed) ...[
                      if (index > 0)
                        const SizedBox(height: AppSpacing.sectionGap),
                      block,
                    ],
                    const Spacer(),
                    const SizedBox(height: AppSpacing.sectionGap),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The greeting and the phrase at the top of A7.
class _Heading extends StatelessWidget {
  const new({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineLarge),
          ),
          Text(
            householdChoicePhrase,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Crea una casa": the highlighted card with the band, the cookie with
/// the house to add, title, text and the arrow. The whole card is one
/// button for the screen reader.
class _CreateCard extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return HighlightCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '$createCardTitle. $createCardText',
      child: _CardContent(
        badge: SizedBox.square(
          dimension: HouseholdChoiceScreen.badgeSize,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.tertiary,
              shape: const CookieBorder(),
            ),
            child: Icon(
              Symbols.add_home_rounded,
              size: HouseholdChoiceScreen.badgeIconSize,
              color: scheme.onTertiary,
            ),
          ),
        ),
        title: createCardTitle,
        text: createCardText,
        textColor: context.appColors.suPrimarioTenue,
      ),
    );
  }
}

/// "Ho un invito": a card of the surface, with the link in a circle, title,
/// text and the arrow. The whole card is one button for the screen reader.
class _JoinCard extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      button: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      color: scheme.surfaceContainerLow,
      semanticLabel: '$joinCardTitle. $joinCardText',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _CardContent(
          badge: SizedBox.square(
            dimension: HouseholdChoiceScreen.badgeSize,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerHighest,
                shape: const CircleBorder(),
              ),
              child: Icon(
                Symbols.link_rounded,
                size: HouseholdChoiceScreen.badgeIconSize,
                color: scheme.primary,
              ),
            ),
          ),
          title: joinCardTitle,
          text: joinCardText,
          titleColor: scheme.onSurface,
          textColor: scheme.onSurfaceVariant,
          arrowColor: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Inside a card of A7: [badge] at the top, 32 above the [title] and its
/// [text], with the arrow at the bottom end.
class _CardContent extends StatelessWidget {
  const new({
    required this.badge,
    required this.title,
    required this.text,
    required this.textColor,
    this.titleColor,
    this.arrowColor,
  });

  final Widget badge;
  final String title;
  final String text;
  final Color textColor;

  /// Null for the colour of the card: white on the highlighted one.
  final Color? titleColor;
  final Color? arrowColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xxl,
      children: [
        badge,
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: AppSpacing.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xxs,
                children: [
                  Text(
                    title,
                    style: textTheme.titleLarge?.copyWith(color: titleColor),
                  ),
                  Text(
                    text,
                    style: textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.arrow_forward_rounded,
              size: AppSizes.icon,
              color: arrowColor,
            ),
          ],
        ),
      ],
    );
  }
}
