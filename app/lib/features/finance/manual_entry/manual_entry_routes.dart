import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:homemade/core/router/screen_catalog.dart';
import 'package:homemade/design/placeholder_screen.dart';
import 'package:material_ui/material_ui.dart';

/// New entry (F2), full screen above the Finance section.
RouteBase manualEntryRoute(GlobalKey<NavigatorState> rootKey) =>
    placeholderRoute(
      'F2',
      path: 'finance/new/:kind',
      parentNavigatorKey: rootKey,
    );

/// Opens the "+" menu of Finance (F1), from which F2 opens.
Future<void> showManualEntryMenu(BuildContext context) =>
    showPlaceholderSheet(context, screenByCode('F1'));
