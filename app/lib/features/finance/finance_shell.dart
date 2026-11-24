import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/fade_through_stack.dart';
import 'package:homemade/design/section_rail.dart';
import 'package:homemade/features/finance/accounts/accounts_routes.dart';
import 'package:homemade/features/finance/analytics/analytics_routes.dart';
import 'package:homemade/features/finance/manual_entry/manual_entry_routes.dart';
import 'package:homemade/features/finance/summary/summary_routes.dart';
import 'package:homemade/features/finance/transactions/transactions_routes.dart';
import 'package:homemade/theme/window_class.dart';
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

/// A tab of the Finance section.
typedef _Tab = ({IconData icon, String label});

/// The four tabs, in the order of the bars: the bottom bar and the side bar
/// both build their destinations from here.
const List<_Tab> _tabs = [
  (icon: Symbols.dashboard_rounded, label: 'Riepilogo'),
  (icon: Symbols.receipt_long_rounded, label: 'Movimenti'),
  (icon: Symbols.insights_rounded, label: 'Analisi'),
  (icon: Symbols.account_balance_rounded, label: 'Conti'),
];

/// The icon of [tab], filled when [selected]. A badge (Movimenti, iteration
/// 5) goes around it here, and shows on both bars.
Widget _tabIcon(_Tab tab, {required bool selected}) =>
    selected ? Icon(tab.icon, fill: 1) : Icon(tab.icon);

/// Top bar with "‹ Finanze", navigation bar and "+" button around the
/// Finance tabs. The bar is at the bottom on a compact window and at the
/// side from the medium class (`docs/spec/navigazione.md`, section 5).
class FinanceShell extends StatelessWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Tabs with the "+" button: Summary and Transactions.
  static const _tabsWithAddButton = 2;

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    final sideBar = WindowClass.of(context).hasSideBar;
    final addButton = index < _tabsWithAddButton
        ? FloatingActionButton(
            tooltip: 'Aggiungi',
            onPressed: () => unawaited(showManualEntryMenu(context)),
            child: const Icon(Symbols.add_rounded),
          )
        : null;

    void select(int selected) => navigationShell.goBranch(
      selected,
      // Tapping the current tab goes back to its first screen.
      initialLocation: selected == index,
    );

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
        // The tabs stay in the same place of the tree, with or without the
        // side bar next to them: when the window changes class their
        // navigators and stacks are kept.
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideBar)
              SectionRail(
                selectedIndex: index,
                onDestinationSelected: select,
                action: addButton,
                destinations: [
                  for (final tab in _tabs)
                    NavigationRailDestination(
                      icon: _tabIcon(tab, selected: false),
                      selectedIcon: _tabIcon(tab, selected: true),
                      label: Text(tab.label),
                    ),
                ],
              ),
            Expanded(child: navigationShell),
          ],
        ),
        floatingActionButton: sideBar ? null : addButton,
        bottomNavigationBar: sideBar
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: select,
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(
                      icon: _tabIcon(tab, selected: false),
                      selectedIcon: _tabIcon(tab, selected: true),
                      label: tab.label,
                    ),
                ],
              ),
      ),
    );
  }
}
