import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:material_ui/material_ui.dart';

/// Analytics tab (G1) with reports (G2).
StatefulShellBranch analyticsBranch(GlobalKey<NavigatorState> rootKey) =>
    StatefulShellBranch(
      routes: [
        placeholderRoute(
          'G1',
          path: 'finance/analytics',
          embedded: true,
          routes: [
            placeholderRoute(
              'G2',
              path: 'reports',
              parentNavigatorKey: rootKey,
            ),
          ],
        ),
      ],
    );
