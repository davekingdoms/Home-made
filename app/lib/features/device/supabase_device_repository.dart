import 'package:homemade/features/device/device_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Postgres code of a unique violation.
const uniqueViolation = '23505';

/// [DeviceRepository] on the `devices` table, under the policy of the owner.
class SupabaseDeviceRepository implements DeviceRepository {
  const new(this._client);

  final SupabaseClient _client;

  @override
  Future<void> insert({
    required String id,
    required String userId,
    required String platform,
  }) async {
    try {
      // No row back (return=minimal): the id is already on the device.
      await _client.from('devices').insert({
        'id': id,
        'user_id': userId,
        'platform': platform,
      });
    } on PostgrestException catch (error) {
      // The row is already there: a previous insert got through even if its
      // answer did not.
      if (error.code != uniqueViolation) rethrow;
    }
  }

  @override
  Future<void> touch(String id, DateTime at) async {
    await _client
        .from('devices')
        .update({'last_seen_at': at.toUtc().toIso8601String()})
        .eq('id', id);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('devices').delete().eq('id', id);
  }
}
