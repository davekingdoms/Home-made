import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:homemade/features/settings/account_screen.dart';

/// Settings (I1–I10), opened from the avatar of the hub.
RouteBase settingsRoute() => placeholderRoute(
  'I1',
  path: 'settings',
  routes: [
    GoRoute(
      path: 'account',
      builder: (context, state) => const AccountScreen(),
    ),
    placeholderRoute('I3', path: 'appearance'),
    placeholderRoute('I4', path: 'household'),
    placeholderRoute(
      'I5',
      path: 'finance',
      routes: [
        placeholderRoute('I6', path: 'categories'),
        placeholderRoute('I7', path: 'tags'),
        placeholderRoute('I8', path: 'people'),
      ],
    ),
    placeholderRoute('I9', path: 'security'),
    placeholderRoute('I10', path: 'hub'),
  ],
);
