import 'package:flutter/foundation.dart';
import 'package:homemade/features/household/invite_code.dart';
import 'package:homemade/features/household/invite_link.dart';

/// An invite opened from its link on this device and not used yet
/// (`docs/spec/accesso.md`, sections 1 and 11): a value of the device, not
/// of the account, kept until the join, the back from A10 to A7, seven days
/// or the deletion of a demo account. "Esci" keeps it.
@immutable
class PendingInvite {
  const new({required this.token, required this.code, required this.savedAt});

  /// The invite of [link], saved at [savedAt].
  factory fromLink(InviteLinkData link, DateTime savedAt) =>
      PendingInvite(token: link.token, code: link.code, savedAt: savedAt);

  /// Reads what [toJson] wrote; null when [json] is not a pending invite.
  static PendingInvite? fromJson(Object? json) {
    if (json case {
      'token': final String token,
      'code': final String code,
      'savedAt': final String savedAt,
    }) {
      final at = DateTime.tryParse(savedAt);
      if (at == null || !isInviteCode(code)) return null;
      return PendingInvite(token: token, code: code, savedAt: at.toLocal());
    }
    return null;
  }

  /// How long it waits for the join: as long as an invite is valid.
  static const lifetime = Duration(days: 7);

  /// Token of the link.
  final String token;

  /// Code of the invite, without the space and in capitals.
  final String code;

  /// When the link was opened.
  final DateTime savedAt;

  /// Whether it is [lifetime] old at [now].
  bool expiredAt(DateTime now) => !now.isBefore(savedAt.add(lifetime));

  Map<String, Object?> toJson() => {
    'token': token,
    'code': code,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is PendingInvite &&
      other.token == token &&
      other.code == code &&
      other.savedAt.isAtSameMomentAs(savedAt);

  @override
  int get hashCode => Object.hash(token, code, savedAt.microsecondsSinceEpoch);

  /// Never the token nor the code: this may end up in a log.
  @override
  String toString() => 'PendingInvite()';
}
