import 'package:go_router/go_router.dart';
import 'package:homemade/core/router/placeholder_route.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';

/// Create or join a household (A7–A10): the screens of the household step,
/// which the startup gate shows while the account has no household. A9
/// and A10 are placeholders until PR 4.7.
RouteBase householdRoute() => GoRoute(
  path: '/household',
  builder: (context, state) => const HouseholdChoiceScreen(),
  routes: [
    GoRoute(
      path: 'create',
      builder: (context, state) => const CreateHouseholdScreen(),
    ),
    placeholderRoute('A9', path: 'invite'),
    placeholderRoute('A10', path: 'join'),
  ],
);
