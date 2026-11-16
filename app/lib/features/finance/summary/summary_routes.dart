import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:material_ui/material_ui.dart';

/// Summary tab (C1) with balances (C2, C3) and savings (C4).
StatefulShellBranch summaryBranch(GlobalKey<NavigatorState> rootKey) =>
    StatefulShellBranch(
      routes: [
        placeholderRoute(
          'C1',
          path: 'finance/summary',
          embedded: true,
          routes: [
            placeholderRoute(
              'C2',
              path: 'balances',
              parentNavigatorKey: rootKey,
              routes: [
                placeholderRoute(
                  'C3',
                  path: 'people/:personId',
                  parentNavigatorKey: rootKey,
                ),
              ],
            ),
            placeholderRoute(
              'C4',
              path: 'savings',
              parentNavigatorKey: rootKey,
            ),
          ],
        ),
      ],
    );
