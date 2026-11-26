import 'package:flutter/foundation.dart';
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

/// Keys of the errors that `create_invite` raises.
enum CreateInviteError {
  /// The account is not an active member of a household.
  notMember('not_member'),

  /// Active members and open invites already take every place.
  householdFull('household_full');

  new(this.key);

  /// The key in the message of the error.
  final String key;

  /// The error behind [error], thrown by [HouseholdRepository.createInvite];
  /// null for any other failure.
  static CreateInviteError? of(Object error) {
    if (error case PostgrestException(code: 'P0001', :final message)) {
      for (final value in values) {
        if (value.key == message) return value;
      }
    }
    return null;
  }
}

/// Keys that `invite_preview` and `redeem_invite` return in their `error`
/// column, instead of raising them (`docs/spec/schema.md`, sections 1 and
/// 3): the attempts that fail must count.
enum InviteError {
  invalid('invite_invalid'),
  expired('invite_expired'),
  used('invite_used'),
  revoked('invite_revoked'),
  tooManyAttempts('too_many_attempts'),

  /// The account has no profile (only `redeem_invite`).
  noProfile('no_profile'),

  /// The account is already in a household (only `redeem_invite`).
  alreadyMember('already_member'),

  /// A demo account and a real household, or the other way round (only
  /// `redeem_invite`, only on `dev`).
  demoMismatch('invite_demo_mismatch'),

  /// No place left (only `redeem_invite`).
  householdFull('household_full'),

  /// The start date chosen is out of the range (only `redeem_invite`).
  startDateOutOfRange('start_date_out_of_range');

  new(this.key);

  /// The key in the `error` column.
  final String key;

  /// Whether the invite itself is the problem: A10 says so under the field
  /// of the code.
  bool get aboutInvite => switch (this) {
    invalid || expired || used || revoked || tooManyAttempts => true,
    _ => false,
  };

  /// The error with [key]; null without one, which means it went well.
  ///
  /// It throws [UnknownInviteError] for a key the app does not know.
  static InviteError? fromKey(String? key) {
    if (key == null) return null;
    for (final value in values) {
      if (value.key == key) return value;
    }
    throw UnknownInviteError(key);
  }
}

/// A key in the `error` column that the app does not know: a screen treats
/// it as any other failure.
class UnknownInviteError implements Exception {
  const new(this.key);

  /// The key, for the log: a code, never a value.
  final String key;

  @override
  String toString() => 'UnknownInviteError($key)';
}

/// An invite just made by `create_invite`: the only moment the token of its
/// link exists in clear.
@immutable
class CreatedInvite {
  const new({
    required this.id,
    required this.token,
    required this.code,
    this.label,
  });

  final String id;

  /// Token of the link: kept only in memory, while A9 shows the invite.
  final String token;

  /// Code, without the space and in capitals.
  final String code;

  /// "Per chi", or null.
  final String? label;

  /// Never the token nor the code: this may end up in a log.
  @override
  String toString() => 'CreatedInvite($id)';
}

/// An open invite of the household: not used, not revoked, not expired.
/// Read with the columns the members may read, never the hash of the token.
@immutable
class OpenInvite {
  const new({
    required this.id,
    required this.expiresAt,
    required this.createdAt,
    this.label,
  });

  final String id;

  /// "Per chi", or null.
  final String? label;

  final DateTime expiresAt;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is OpenInvite &&
      other.id == id &&
      other.label == label &&
      other.expiresAt == expiresAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, label, expiresAt, createdAt);
}

/// What A9 shows of the household of the signed-in user: its name, for the
/// text of the share, and its open invites, the latest first.
typedef InviteContext = ({String householdName, List<OpenInvite> openInvites});

/// The answer of `invite_preview`: the household of the invite, or why
/// there is none to show.
@immutable
class InvitePreview {
  const new({
    required this.householdName,
    required this.inviterName,
    required this.memberNames,
    required this.householdStartDate,
  });

  final String householdName;

  /// Display name of who invites; null when their account is gone.
  final String? inviterName;

  /// Display names of the active members, in the order they joined.
  final List<String> memberNames;

  /// Start date of the household, a local date at midnight.
  final DateTime householdStartDate;
}

/// The result of `invite_preview`: the preview, or the error of the
/// invite.
typedef InvitePreviewResult = ({InvitePreview? preview, InviteError? error});

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

  /// The name and the open invites of the household of the signed-in user.
  ///
  /// It throws when Supabase cannot be reached or answers with an error.
  Future<InviteContext> readInviteContext();

  /// Creates an invite to the household of the signed-in user, "per"
  /// [label] when given, valid 7 days.
  ///
  /// It throws when Supabase cannot be reached or answers with an error
  /// ([CreateInviteError.of]).
  Future<CreatedInvite> createInvite({String? label});

  /// The household of the invite with [code] or [token] (exactly one of
  /// them), before joining it. Every call counts as an attempt.
  ///
  /// It throws when Supabase cannot be reached or answers with an error, or
  /// [UnknownInviteError].
  Future<InvitePreviewResult> previewInvite({String? code, String? token});

  /// Joins the household of the invite with [code] or [token] (exactly one
  /// of them), from [startDate] (null in a household that has not started,
  /// or for today), with [cashOpeningCents] as the opening balance of the
  /// cash when the start date is the today of the server. Returns null when
  /// it went well, otherwise the error of the server. A second call with
  /// the same invite after a lost answer ends in the same membership.
  ///
  /// It throws when Supabase cannot be reached or answers with an error, or
  /// [UnknownInviteError].
  Future<InviteError?> redeemInvite({
    String? code,
    String? token,
    int? cashOpeningCents,
    DateTime? startDate,
  });
}

/// The repository of the app. `main` overrides it; tests use a fake.
@Riverpod(keepAlive: true)
HouseholdRepository householdRepository(Ref ref) => throw StateError(
  'householdRepositoryProvider must be overridden at startup',
);
