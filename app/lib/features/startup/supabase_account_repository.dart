import 'package:homemade/features/startup/account_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AccountRepository] on Supabase: `profiles`, `user_settings` and
/// `current_member_id()`, all under the policies of the signed-in user.
class SupabaseAccountRepository implements AccountRepository {
  const new(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountStatus> readStatus(String userId) async {
    // The reads are not retried: at startup a missing network shows the
    // saved state at once instead of a long wait.
    final results = await Future.wait<Object?>([
      _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle()
          .retry(enabled: false),
      _client
          .from('user_settings')
          .select('privacy_notice_version')
          .eq('user_id', userId)
          .maybeSingle()
          .retry(enabled: false),
      _client.rpc<Object?>('current_member_id').retry(enabled: false),
    ]);
    final [profile, settings, memberId] = results;
    return AccountStatus(
      hasProfile: profile != null,
      noticeVersion: switch (settings) {
        {'privacy_notice_version': final String version} => version,
        _ => null,
      },
      hasMember: memberId != null,
    );
  }

  @override
  Future<void> saveFirstAccess({
    required String userId,
    required String noticeVersion,
    required DateTime readAt,
    String? displayName,
    String? avatarUrl,
  }) async {
    // The profile comes first: user_settings refers to it. Both writes can
    // be repeated: a retry after a half-done save ends in the same rows.
    if (displayName != null) {
      await _client.from('profiles').upsert({
        'id': userId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
      });
    }
    await _client.from('user_settings').upsert({
      'user_id': userId,
      'privacy_notice_version': noticeVersion,
      'privacy_notice_read_at': readAt.toUtc().toIso8601String(),
    });
  }
}
