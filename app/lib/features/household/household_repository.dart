import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'household_repository.g.dart';

/// Keys of the errors that `create_household` raises
/// (`docs/spec/schema.md`, section 3).
enum CreateHouseholdError {
  /// The account has no profile.
  noProfile('no_profile'),

  /// The account is already an active member of a household: it made one,
  /// or used an invite, on another device.
  alreadyMember('already_member'),

  /// The start date is out of the range the server accepts.
  startDateOutOfRange('start_date_out_of_range');

  new(this.key);

  /// The key in the message of the error.
  final String key;

  /// The error behind [error], thrown by [HouseholdRepository];
  /// null for any other failure.
  static CreateHouseholdError? of(Object error) {
    if (error case PostgrestException(code: 'P0001', :final message)) {
      for (final value in values) {
        if (value.key == message) return value;
      }
    }
    return null;
  }
}

/// The household of the signed-in user on Supabase.
abstract interface class HouseholdRepository {
  /// Creates the household [id] called [name], from [startDate], with the
  /// signed-in user as its first member and their cash account; with
  /// [cashOpeningCents], the opening balance of that account, which the
  /// server keeps only when [startDate] is its today.
  ///
  /// A second call with the same [id] creates nothing: a retry after a lost
  /// answer ends in the same household. It throws when Supabase cannot be
  /// reached or answers with an error ([CreateHouseholdError.of]).
  Future<void> createHousehold({
    required String id,
    required String name,
    required DateTime startDate,
    int? cashOpeningCents,
  });
}

/// The repository of the app. `main` overrides it; tests use a fake.
@Riverpod(keepAlive: true)
HouseholdRepository householdRepository(Ref ref) => throw StateError(
  'householdRepositoryProvider must be overridden at startup',
);
