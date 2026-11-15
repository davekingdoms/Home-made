import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/features/finance/accounts/accounts_routes.dart';
import 'package:homemade/features/finance/analytics/analytics_routes.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/finance/summary/summary_routes.dart';
import 'package:homemade/features/finance/transactions/transactions_routes.dart';
import 'package:material_ui/material_ui.dart';

/// The Finance section: four tabs, each with its own navigation stack.
RouteBase financeRoute(GlobalKey<NavigatorState> rootKey) =>
    StatefulShellRoute.indexedStack(
      parentNavigatorKey: rootKey,
      builder: (context, state, navigationShell) =>
          FinanceShell(navigationShell: navigationShell),
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
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Finanze'),
            ),
          ),
        ),
        body: navigationShell,
        floatingActionButton: index < _tabsWithAddButton
            ? FloatingActionButton(
                tooltip: 'Aggiungi',
                onPressed: () => unawaited(showManualEntryMenu(context)),
                child: const Icon(Icons.add_rounded),
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
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Riepilogo',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Movimenti',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Analisi',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance_rounded),
              label: 'Conti',
            ),
          ],
        ),
      ),
    );
  }
}
