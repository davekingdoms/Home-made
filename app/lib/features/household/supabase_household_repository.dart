import 'package:homemade/features/household/household_dates.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [HouseholdRepository] on the functions of the households and of the
/// invites (`create_household`, `create_invite`, `invite_preview`,
/// `redeem_invite`), which check the signed-in user themselves, and on the
/// tables the members read under their policies.
class SupabaseHouseholdRepository implements HouseholdRepository {
  const new(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient _client;

  /// Time of the device, for the invites still open.
  final DateTime Function() _now;

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

  @override
  Future<InviteContext> readInviteContext() async {
    final results = await Future.wait<Object?>([
      _client.from('households').select('name').maybeSingle(),
      // The columns the members may read: never token_hash.
      _client
          .from('invites')
          .select('id, label, expires_at, created_at')
          .isFilter('used_at', null)
          .isFilter('revoked_at', null)
          .gt('expires_at', _now().toUtc().toIso8601String())
          // The latest first.
          .order('created_at', ascending: false),
    ]);
    final [household, invites] = results;
    final name = switch (household) {
      {'name': final String name} => name,
      _ => throw StateError('no household for the signed-in user'),
    };
    return (
      householdName: name,
      openInvites: [
        for (final row in invites! as List<Object?>)
          if (row case {
            'id': final String id,
            'label': final String? label,
            'expires_at': final String expiresAt,
            'created_at': final String createdAt,
          })
            OpenInvite(
              id: id,
              label: label,
              expiresAt: DateTime.parse(expiresAt).toLocal(),
              createdAt: DateTime.parse(createdAt).toLocal(),
            ),
      ],
    );
  }

  @override
  Future<CreatedInvite> createInvite({String? label}) async {
    final rows = await _client.rpc<List<Object?>>(
      'create_invite',
      params: {'label': label},
    );
    return switch (rows) {
      [
        {
          'invite_id': final String id,
          'token': final String token,
          'code': final String code,
        },
      ] =>
        CreatedInvite(id: id, token: token, code: code, label: label),
      _ => throw StateError('create_invite returned no invite'),
    };
  }

  @override
  Future<InvitePreviewResult> previewInvite({
    String? code,
    String? token,
  }) async {
    final rows = await _client.rpc<List<Object?>>(
      'invite_preview',
      params: {'code': code, 'token': token},
    );
    final row = switch (rows) {
      [final Map<String, Object?> row] => row,
      _ => throw StateError('invite_preview returned no row'),
    };
    final error = InviteError.fromKey(row['error'] as String?);
    if (error != null) return (preview: null, error: error);
    return switch (row) {
      {
        'household_name': final String householdName,
        'inviter_name': final String? inviterName,
        'member_names': final List<Object?> memberNames,
        'household_start_date': final String startDate,
      } =>
        (
          preview: InvitePreview(
            householdName: householdName,
            inviterName: inviterName,
            memberNames: memberNames.whereType<String>().toList(),
            householdStartDate: dateOnly(DateTime.parse(startDate)),
          ),
          error: null,
        ),
      _ => throw StateError('invite_preview returned no household'),
    };
  }

  @override
  Future<InviteError?> redeemInvite({
    String? code,
    String? token,
    int? cashOpeningCents,
    DateTime? startDate,
  }) async {
    final rows = await _client.rpc<List<Object?>>(
      'redeem_invite',
      params: {
        'code': code,
        'token': token,
        'cash_opening_cents': cashOpeningCents,
        'start_date': startDate == null ? null : isoDate(startDate),
      },
    );
    return switch (rows) {
      [{'error': final String? error}] => InviteError.fromKey(error),
      _ => throw StateError('redeem_invite returned no row'),
    };
  }
}
