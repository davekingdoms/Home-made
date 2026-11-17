import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/fade_through_stack.dart';
import 'package:homemade/features/finance/accounts/accounts_routes.dart';
import 'package:homemade/features/finance/analytics/analytics_routes.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/finance/summary/summary_routes.dart';
import 'package:homemade/features/finance/transactions/transactions_routes.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The Finance section: four tabs, each with its own navigation stack, that
/// "fade through" one another.
RouteBase financeRoute(GlobalKey<NavigatorState> rootKey) => StatefulShellRoute(
  parentNavigatorKey: rootKey,
  builder: (context, state, navigationShell) =>
      FinanceShell(navigationShell: navigationShell),
  navigatorContainerBuilder: (context, navigationShell, children) =>
      FadeThroughStack(
        currentIndex: navigationShell.currentIndex,
        children: children,
      ),
  branches: [
    summaryBranch(rootKey),
    transactionsBranch(rootKey),
    analyticsBranch(rootKey),
    accountsBranch(rootKey),
  ],
);

/// Top bar with "‹ Finanze", bottom bar and "+" button around the Finance
/// tabs.
class FinanceShell extends StatelessWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Tabs with the "+" button: Summary and Transactions.
  static const _tabsWithAddButton = 2;

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    return PopScope(
      // Back goes from the other tabs to the first one, and from there to
      // the hub.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 4,
          title: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => context.go(screenByCode('B1').location!),
              icon: const Icon(Symbols.chevron_left_rounded),
              label: const Text('Finanze'),
            ),
          ),
        ),
        body: navigationShell,
        floatingActionButton: index < _tabsWithAddButton
            ? FloatingActionButton(
                tooltip: 'Aggiungi',
                onPressed: () => unawaited(showManualEntryMenu(context)),
                child: const Icon(Symbols.add_rounded),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (selected) => navigationShell.goBranch(
            selected,
            // Tapping the current tab goes back to its first screen.
            initialLocation: selected == index,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Symbols.dashboard_rounded),
              selectedIcon: Icon(Symbols.dashboard_rounded, fill: 1),
              label: 'Riepilogo',
            ),
            NavigationDestination(
              icon: Icon(Symbols.receipt_long_rounded),
              selectedIcon: Icon(Symbols.receipt_long_rounded, fill: 1),
              label: 'Movimenti',
            ),
            NavigationDestination(
              icon: Icon(Symbols.insights_rounded),
              selectedIcon: Icon(Symbols.insights_rounded, fill: 1),
              label: 'Analisi',
            ),
            NavigationDestination(
              icon: Icon(Symbols.account_balance_rounded),
              selectedIcon: Icon(Symbols.account_balance_rounded, fill: 1),
              label: 'Conti',
            ),
          ],
        ),
      ),
    );
  }
}
