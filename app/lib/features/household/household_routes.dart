import 'package:go_router/go_router.dart';
import 'package:homemade/features/household/create_household_screen.dart';
import 'package:homemade/features/household/household_choice_screen.dart';
import 'package:homemade/features/household/invite_screen.dart';
import 'package:homemade/features/household/join_household_screen.dart';

/// Create or join a household (A7–A10): the screens of the household step,
/// which the startup gate shows while the account has no household; A9
/// also right after "Crea" of A8, and A10 in place of A7 with a pending
/// invite.
RouteBase householdRoute() => GoRoute(
  path: '/household',
  builder: (context, state) => const HouseholdChoiceScreen(),
  routes: [
    GoRoute(
      path: 'create',
      builder: (context, state) => const CreateHouseholdScreen(),
    ),
    GoRoute(path: 'invite', builder: (context, state) => const InviteScreen()),
    GoRoute(
      path: 'join',
      builder: (context, state) => const JoinHouseholdScreen(),
    ),
  ],
);
