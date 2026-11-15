import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:material_ui/material_ui.dart';

/// Transactions tab (D1) with the transaction detail (E1).
StatefulShellBranch transactionsBranch(GlobalKey<NavigatorState> rootKey) =>
    StatefulShellBranch(
      routes: [
        placeholderRoute(
          'D1',
          path: 'finance/transactions',
          embedded: true,
          routes: [
            placeholderRoute(
              'E1',
              path: ':transactionId',
              parentNavigatorKey: rootKey,
            ),
          ],
        ),
      ],
    );
