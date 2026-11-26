import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [HouseholdRepository] on the functions of the households
/// (`create_household`), which check the signed-in user themselves.
class SupabaseHouseholdRepository implements HouseholdRepository {
  const new(this._client);

  final SupabaseClient _client;

  @override
  Future<void> createHousehold({
    required String id,
    required String name,
    required DateTime startDate,
    int? cashOpeningCents,
  }) async {
    await _client.rpc<Object?>(
      'create_household',
      params: {
        'id': id,
        'name': name,
        'start_date': isoDate(startDate),
        'cash_opening_cents': cashOpeningCents,
      },
    );
  }
}
