import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/household/invite_code.dart';
import 'package:homemade/features/household/invite_link.dart';
import 'package:homemade/features/household/pending_invite.dart';

import 'helpers/fakes.dart';

/// The invites of the real app, on an invented site.
const _prod = InviteLinks(
  pagesBaseUrl: 'https://example.pages.dev',
  flavor: null,
);

/// The invites of the dev app, on the same site.
const _dev = InviteLinks(
  pagesBaseUrl: 'https://example.pages.dev',
  flavor: 'dev',
);

/// [text] typed or pasted into an empty field of the code.
TextEditingValue _type(String text) =>
    const InviteCodeFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

void main() {
  group('the code', () {
    test('is read without spaces and dashes, in capitals', () {
      expect(normalizeInviteCode('k7qm-x2pa'), 'K7QMX2PA');
      expect(normalizeInviteCode(' K7QM X2PA '), 'K7QMX2PA');
    });

    test('is of the alphabet of create_invite', () {
      expect(isInviteCode('K7QMX2PA'), isTrue);
      expect(isInviteCode('K7QMX2P'), isFalse);
      // 0, O, 1, I, L are not in the alphabet.
      expect(isInviteCode('K7QMX2P0'), isFalse);
      expect(isInviteCode('K7QMX2PO'), isFalse);
      expect(isInviteCode('K7QMX2PI'), isFalse);
      expect(isInviteCode('k7qmx2pa'), isFalse);
    });

    test('shows in two groups of 4', () {
      expect(formatInviteCode('K7QMX2PA'), 'K7QM X2PA');
      expect(formatInviteCode('K7QM'), 'K7QM');
      expect(formatInviteCode('K7QMX'), 'K7QM X');
    });

    test('is read aloud one character at a time', () {
      expect(spokenInviteCode('K7QMX2PA'), 'K 7 Q M, X 2 P A');
    });
  });

  group('the field of the code', () {
    test('keeps letters and digits, in capitals, with the space', () {
      expect(_type('k7qm-x2pa').text, 'K7QM X2PA');
      expect(_type('K7QM X2PA').text, 'K7QM X2PA');
      expect(_type('k7q').text, 'K7Q');
      expect(_type('k7qmx').text, 'K7QM X');
    });

    test('keeps at most 8 characters', () {
      expect(_type('K7QMX2PAZZ').text, 'K7QM X2PA');
    });

    test('drops what is not a letter or a digit', () {
      expect(_type('K7.QM/X2_PA!').text, 'K7QM X2PA');
      expect(_type('èéà').text, '');
    });

    test('keeps the caret after the same character', () {
      expect(_type('k7qm-x2pa').selection.baseOffset, 9);
      expect(_type('k7q').selection.baseOffset, 3);
    });
  });

  group('the link', () {
    test('has token and code in the fragment, on the path of the flavor', () {
      expect(
        _prod.link(token: inventedToken, code: 'K7QM X2PA').toString(),
        'https://example.pages.dev/invite/#t=$inventedToken&c=K7QMX2PA',
      );
      expect(
        _dev.link(token: inventedToken, code: 'K7QMX2PA').toString(),
        'https://example.pages.dev/dev/invite/#t=$inventedToken&c=K7QMX2PA',
      );
    });

    test('is the path of the invites of the flavor only', () {
      final link = _prod.link(token: inventedToken, code: 'K7QMX2PA');
      expect(_prod.matches(link), isTrue);
      expect(_prod.matches(Uri.parse('/invite')), isTrue);
      expect(_prod.matches(Uri.parse('/invite/#t=x')), isTrue);
      expect(_prod.matches(Uri.parse('/dev/invite')), isFalse);
      expect(_dev.matches(Uri.parse('/dev/invite')), isTrue);
      expect(_dev.matches(link), isFalse);
      expect(_prod.matches(Uri.parse('/invites')), isFalse);
      expect(_prod.matches(Uri.parse('/household/join')), isFalse);
    });

    test('of another site, or without https, is not an invite', () {
      expect(
        _prod.matches(Uri.parse('https://other.example/invite/#t=x&c=y')),
        isFalse,
      );
      expect(
        _prod.matches(Uri.parse('http://example.pages.dev/invite/')),
        isFalse,
      );
    });

    test('gives back token and code', () {
      final link = _prod.link(token: inventedToken, code: 'K7QMX2PA');
      expect(
        _prod.read(link),
        const InviteLinkData(token: inventedToken, code: 'K7QMX2PA'),
      );
    });

    test('takes the code in small letters too', () {
      expect(
        _prod.read(Uri.parse('/invite/#t=$inventedToken&c=k7qmx2pa'))?.code,
        'K7QMX2PA',
      );
    });

    test('takes the two values in any order', () {
      expect(
        _prod.read(Uri.parse('/invite/#c=K7QMX2PA&t=$inventedToken')),
        isNotNull,
      );
    });

    for (final (name, fragment) in [
      ('without fragment', ''),
      ('without token', 'c=K7QMX2PA'),
      ('without code', 't=$inventedToken'),
      ('with a short token', 't=${inventedToken.substring(1)}&c=K7QMX2PA'),
      ('with a token not in base64url', 't=${'+' * 43}&c=K7QMX2PA'),
      ('with a short code', 't=$inventedToken&c=K7QMX2P'),
      ('with a code out of the alphabet', 't=$inventedToken&c=K7QMX2P0'),
      ('with the space in the code', 't=$inventedToken&c=K7QM%20X2PA'),
      ('with a value twice', 't=$inventedToken&t=$inventedToken&c=K7QMX2PA'),
      ('with another key', 't=$inventedToken&c=K7QMX2PA&x=1'),
      ('with an empty pair', 't=$inventedToken&&c=K7QMX2PA'),
    ]) {
      test('$name is not valid', () {
        expect(_prod.read(Uri.parse('/invite/#$fragment')), isNull);
      });
    }

    test('never tells token or code in its text', () {
      const link = InviteLinkData(token: inventedToken, code: 'K7QMX2PA');
      expect('$link', isNot(contains(inventedToken)));
      expect('$link', isNot(contains('K7QMX2PA')));
    });
  });

  group('the pending invite', () {
    final savedAt = DateTime(2031, 3, 15, 10);
    final invite = PendingInvite(
      token: inventedToken,
      code: 'K7QMX2PA',
      savedAt: savedAt,
    );

    test('is saved and read back', () {
      expect(PendingInvite.fromJson(invite.toJson()), invite);
    });

    test('something else is no pending invite', () {
      expect(PendingInvite.fromJson(null), isNull);
      expect(PendingInvite.fromJson({'token': inventedToken}), isNull);
      expect(
        PendingInvite.fromJson({
          'token': inventedToken,
          'code': 'K7QMX2P0',
          'savedAt': savedAt.toIso8601String(),
        }),
        isNull,
      );
    });

    test('lasts seven days', () {
      expect(invite.expiredAt(savedAt.add(const Duration(days: 6))), isFalse);
      expect(invite.expiredAt(savedAt.add(const Duration(days: 7))), isTrue);
    });

    test('never tells token or code in its text', () {
      expect('$invite', isNot(contains(inventedToken)));
      expect('$invite', isNot(contains('K7QMX2PA')));
    });
  });
}
