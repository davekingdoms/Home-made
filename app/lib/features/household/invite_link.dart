import 'package:flutter/foundation.dart';
import 'package:homemade/core/config/app_config.dart';
import 'package:homemade/core/config/app_flavor.dart';
import 'package:homemade/features/household/invite_code.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'invite_link.g.dart';

/// The links of the invites of this build: its Pages site and its flavor.
@Riverpod(keepAlive: true)
InviteLinks inviteLinks(Ref ref) => InviteLinks(
  pagesBaseUrl: ref.watch(appConfigProvider).pagesBaseUrl,
  flavor: AppFlavor.current,
);

/// Token of the link of an invite: 32 random bytes in base64url, without
/// the padding (`create_invite`).
final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// What the link of an invite carries: the token, and the code for the
/// page of Pages and for the field of A10.
@immutable
class InviteLinkData {
  const new({required this.token, required this.code});

  /// Token of the link, as `create_invite` returned it.
  final String token;

  /// Code of the invite, without the space and in capitals.
  final String code;

  @override
  bool operator ==(Object other) =>
      other is InviteLinkData && other.token == token && other.code == code;

  @override
  int get hashCode => Object.hash(token, code);

  /// Never the token nor the code: this may end up in a log.
  @override
  String toString() => 'InviteLinkData()';
}

/// The links of the invites (`docs/spec/navigazione.md`, section 2): App
/// Links to the page of the invites on Pages, `/invite/` for the `prod`
/// flavor and `/dev/invite/` for `dev`, so that the two apps, which fit on
/// the same phone, never take each other's links.
///
/// Token and code go in the fragment, which the browser never sends to the
/// server: they reach neither the logs of Pages nor a `Referer`.
class InviteLinks {
  const new({required this.pagesBaseUrl, required this.flavor});

  /// Address of the Pages site, without the final `/` (`PAGES_BASE_URL`).
  final String pagesBaseUrl;

  /// Flavor of the build; null, as in the tests, is the real app.
  final String? flavor;

  /// Path of the invites of [flavor], without the final `/`.
  String get path => flavor == AppFlavor.dev ? '/dev/invite' : '/invite';

  /// The link of the invite with [token] and [code]:
  /// `{PAGES_BASE_URL}/invite/#t={token}&c={code}`.
  Uri link({required String token, required String code}) =>
      Uri.parse('$pagesBaseUrl$path/#t=$token&c=${normalizeInviteCode(code)}');

  /// Whether [uri] is the path of the invites, as an App Link brings it to
  /// the router: the whole address, with or without the final `/`, or its
  /// path only.
  bool matches(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority) {
      final base = Uri.tryParse(pagesBaseUrl);
      if (base == null || uri.scheme != 'https' || uri.host != base.host) {
        return false;
      }
    }
    return uri.path == path || uri.path == '$path/';
  }

  /// Token and code in the fragment of [uri], read strictly: exactly `t`
  /// and `c`, once each; `t` of 43 characters of base64url, `c` of 8
  /// characters of the alphabet of the codes, in capitals or not. Null
  /// when the fragment is missing or malformed.
  InviteLinkData? read(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    final values = <String, String>{};
    for (final pair in fragment.split('&')) {
      final separator = pair.indexOf('=');
      if (separator <= 0) return null;
      final key = pair.substring(0, separator);
      if (key != 't' && key != 'c') return null;
      if (values.containsKey(key)) return null;
      values[key] = pair.substring(separator + 1);
    }
    final token = values['t'];
    final code = values['c'];
    if (token == null || code == null) return null;
    if (!_token.hasMatch(token)) return null;
    final normalized = code.toUpperCase();
    if (!isInviteCode(normalized)) return null;
    return InviteLinkData(token: token, code: normalized);
  }
}
