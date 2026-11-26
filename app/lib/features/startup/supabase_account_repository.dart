import 'package:homemade/features/startup/account_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AccountRepository] on Supabase: `profiles` (with the display name, for
/// the greeting of A7), `user_settings`, `current_member_id()` and
/// `delete_my_demo_account()`, all under the policies of the signed-in user.
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
          .select('id, is_demo, display_name')
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
      isDemo: switch (profile) {
        {'is_demo': true} => true,
        _ => false,
      },
      displayName: switch (profile) {
        {'display_name': final String name} => name,
        _ => null,
      },
    );
  }

  @override
  Future<void> saveFirstAccess({
    required String userId,
    required String noticeVersion,
    required DateTime readAt,
    String? displayName,
    String? avatarUrl,
    bool isDemo = false,
  }) async {
    // The profile comes first: user_settings refers to it. Both writes can
    // be repeated: a retry after a half-done save ends in the same rows.
    // The flag goes only when it is true: the server refuses to change it,
    // and without it the save of a real account is the same as before.
    if (displayName != null) {
      await _client.from('profiles').upsert({
        'id': userId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        if (isDemo) 'is_demo': true,
      });
    }
    await _client.from('user_settings').upsert({
      'user_id': userId,
      'privacy_notice_version': noticeVersion,
      'privacy_notice_read_at': readAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> deleteDemoAccount() async {
    await _client.rpc<Object?>('delete_my_demo_account');
  }
}
