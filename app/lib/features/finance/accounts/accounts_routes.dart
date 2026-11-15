import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:material_ui/material_ui.dart';

/// Accounts tab (H1) with bank linking (H4), manual account (H5) and the
/// account detail (H2).
StatefulShellBranch accountsBranch(
  GlobalKey<NavigatorState> rootKey,
) => StatefulShellBranch(
  routes: [
    placeholderRoute(
      'H1',
      path: 'finance/accounts',
      embedded: true,
      routes: [
        // Fixed paths before the parameter, or ":accountId" takes them.
        placeholderRoute('H4', path: 'link', parentNavigatorKey: rootKey),
        placeholderRoute('H5', path: 'new', parentNavigatorKey: rootKey),
        placeholderRoute('H2', path: ':accountId', parentNavigatorKey: rootKey),
      ],
    ),
  ],
);
