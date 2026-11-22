import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_status.g.dart';

/// Version of the privacy notice the app asks to read (A3).
///
/// `p1` is the first provisional notice, for the trials among the members of
/// the household. A new version shows A3 again, with the checkbox only.
const privacyNoticeVersion = 'p1';

/// Path of the privacy notice on the Pages site.
const privacyNoticePath = '/privacy/';

/// What the server knows about the signed-in account, for the startup steps
/// (`docs/spec/accesso.md`, section 1). The device keeps the last one read
/// for each account, to start offline.
@immutable
class AccountStatus {
  const new({
    required this.hasProfile,
    required this.noticeVersion,
    required this.hasMember,
  });

  /// Reads what [toJson] wrote; null when [json] is not a status.
  static AccountStatus? fromJson(Object? json) {
    if (json case {
      'hasProfile': final bool hasProfile,
      'noticeVersion': final String? noticeVersion,
      'hasMember': final bool hasMember,
    }) {
      return AccountStatus(
        hasProfile: hasProfile,
        noticeVersion: noticeVersion,
        hasMember: hasMember,
      );
    }
    return null;
  }

  /// Whether the account has its profile (name and photo).
  final bool hasProfile;

  /// Version of the privacy notice read, or null.
  final String? noticeVersion;

  /// Whether the account is an active member of a household.
  final bool hasMember;

  /// Whether the current version of the privacy notice is read.
  bool get noticeRead => noticeVersion == privacyNoticeVersion;

  AccountStatus copyWith({bool? hasProfile, String? noticeVersion}) =>
      AccountStatus(
        hasProfile: hasProfile ?? this.hasProfile,
        noticeVersion: noticeVersion ?? this.noticeVersion,
        hasMember: hasMember,
      );

  Map<String, Object?> toJson() => {
    'hasProfile': hasProfile,
    'noticeVersion': noticeVersion,
    'hasMember': hasMember,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountStatus &&
      other.hasProfile == hasProfile &&
      other.noticeVersion == noticeVersion &&
      other.hasMember == hasMember;

  @override
  int get hashCode => Object.hash(hasProfile, noticeVersion, hasMember);
}

/// Reads and writes the account of the signed-in user on Supabase: its
/// profile, its settings and whether it is a member of a household.
abstract interface class AccountRepository {
  /// What the server knows about the account [userId].
  ///
  /// It throws when Supabase cannot be reached or answers with an error.
  Future<AccountStatus> readStatus(String userId);

  /// Saves the first access (A3) of [userId]: the profile, when
  /// [displayName] is given, then the version of the notice read at
  /// [readAt].
  ///
  /// It throws when Supabase cannot be reached or answers with an error.
  Future<void> saveFirstAccess({
    required String userId,
    required String noticeVersion,
    required DateTime readAt,
    String? displayName,
    String? avatarUrl,
  });
}

/// The repository of the app. `main` overrides it; tests use a fake.
@Riverpod(keepAlive: true)
AccountRepository accountRepository(Ref ref) =>
    throw StateError('accountRepositoryProvider must be overridden at startup');
