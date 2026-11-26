import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/device/supabase_device_repository.dart';
import 'package:homemade/features/household/household_repository.dart';
import 'package:homemade/features/household/supabase_household_repository.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:homemade/features/startup/supabase_account_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Invented ids.
const _userId = '00000000-0000-4000-8000-00000000a001';
const _deviceId = '00000000-0000-4000-8000-00000000d001';
const _householdId = '00000000-0000-4000-8000-00000000c001';

/// A Supabase client whose requests [handler] answers, with no network.
/// The requests are collected in [requests].
SupabaseClient _client(
  List<http.Request> requests,
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'placeholder',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request);
      final response = await handler(request);
      // The client reads the request back from the response.
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// The error PostgREST sends for a unique violation, with invented values.
http.Response get _duplicate => _json({
  'code': '23505',
  'details': 'Key already exists.',
  'hint': null,
  'message': 'duplicate key value violates unique constraint',
}, 409);

void main() {
  group('devices', () {
    test('inserts the row of the device without asking it back', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 201));

      await SupabaseDeviceRepository(client)
          .insert(id: _deviceId, userId: _userId, platform: 'android');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/devices');
      // Without return=representation PostgREST sends no row back.
      expect(
        request.headers['Prefer'] ?? '',
        isNot(contains('return=representation')),
      );
      expect(jsonDecode(request.body), {
        'id': _deviceId,
        'user_id': _userId,
        'platform': 'android',
      });
    });

    test('takes a 23505 as a row already saved', () async {
      final client = _client([], (_) async => _duplicate);

      await expectLater(
        SupabaseDeviceRepository(client)
            .insert(id: _deviceId, userId: _userId, platform: 'android'),
        completes,
      );
    });

    test('throws any other error', () async {
      final client = _client(
        [],
        (_) async => _json({'code': '42501', 'message': 'denied'}, 403),
      );

      await expectLater(
        SupabaseDeviceRepository(client)
            .insert(id: _deviceId, userId: _userId, platform: 'android'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('deletes and touches only the row of the device', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 204));
      final repository = SupabaseDeviceRepository(client);

      await repository.touch(_deviceId, DateTime.utc(2030, 3, 1, 9));
      await repository.delete(_deviceId);

      final [touch, delete] = requests;
      expect(touch.method, 'PATCH');
      expect(touch.url.queryParameters, {'id': 'eq.$_deviceId'});
      expect(jsonDecode(touch.body), {
        'last_seen_at': '2030-03-01T09:00:00.000Z',
      });
      expect(delete.method, 'DELETE');
      expect(delete.url.queryParameters, {'id': 'eq.$_deviceId'});
    });
  });

  group('account', () {
    test('reads profile, settings and membership', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (request) async {
        return switch (request.url.path) {
          // maybeSingle on a GET reads a list of at most one row.
          '/rest/v1/profiles' => _json([
            {'id': _userId},
          ]),
          '/rest/v1/user_settings' => _json([
            {'privacy_notice_version': 'p1'},
          ]),
          '/rest/v1/rpc/current_member_id' => _json(
            '00000000-0000-4000-8000-00000000e001',
          ),
          _ => http.Response('', 404),
        };
      });

      final status = await SupabaseAccountRepository(client)
          .readStatus(_userId);

      expect(
        status,
        const AccountStatus(
          hasProfile: true,
          noticeVersion: 'p1',
          hasMember: true,
        ),
      );
      final profile = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/profiles',
      );
      expect(profile.url.queryParameters['id'], 'eq.$_userId');
    });

    test('reads the flag of a demo account', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (request) async {
        return switch (request.url.path) {
          '/rest/v1/profiles' => _json([
            {'id': _userId, 'is_demo': true},
          ]),
          '/rest/v1/user_settings' => _json([
            {'privacy_notice_version': 'p1'},
          ]),
          _ => _json(null),
        };
      });

      final status = await SupabaseAccountRepository(client)
          .readStatus(_userId);

      expect(status.isDemo, isTrue);
      final profile = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/profiles',
      );
      expect(profile.url.queryParameters['select'], contains('is_demo'));
    });

    test('reads the display name of the profile', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (request) async {
        return switch (request.url.path) {
          '/rest/v1/profiles' => _json([
            {'id': _userId, 'is_demo': false, 'display_name': 'Anna Maria'},
          ]),
          _ => _json(null),
        };
      });

      final status = await SupabaseAccountRepository(client)
          .readStatus(_userId);

      expect(status.displayName, 'Anna Maria');
      final profile = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/profiles',
      );
      expect(profile.url.queryParameters['select'], contains('display_name'));
    });

    test('reads a new account as one without anything', () async {
      final client = _client([], (request) async {
        if (request.url.path.startsWith('/rest/v1/rpc/')) return _json(null);
        // maybeSingle on a GET: no row.
        return _json(<Object>[]);
      });

      final status = await SupabaseAccountRepository(client)
          .readStatus(_userId);

      expect(
        status,
        const AccountStatus(
          hasProfile: false,
          noticeVersion: null,
          hasMember: false,
        ),
      );
    });

    test('saves the profile before the notice, as upserts', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 201));

      await SupabaseAccountRepository(client).saveFirstAccess(
        userId: _userId,
        displayName: 'Anna',
        avatarUrl: 'https://example.com/anna.png',
        noticeVersion: 'p1',
        readAt: DateTime.utc(2030, 3, 1, 9),
      );

      final [profile, settings] = requests;
      expect(profile.url.path, '/rest/v1/profiles');
      expect(
        profile.headers['Prefer'],
        contains('resolution=merge-duplicates'),
      );
      expect(jsonDecode(profile.body), {
        'id': _userId,
        'display_name': 'Anna',
        'avatar_url': 'https://example.com/anna.png',
      });
      expect(settings.url.path, '/rest/v1/user_settings');
      expect(jsonDecode(settings.body), {
        'user_id': _userId,
        'privacy_notice_version': 'p1',
        'privacy_notice_read_at': '2030-03-01T09:00:00.000Z',
      });
    });

    test('creates the profile of a demo account with its flag', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 201));

      await SupabaseAccountRepository(client).saveFirstAccess(
        userId: _userId,
        displayName: 'Anna',
        noticeVersion: 'p1',
        readAt: DateTime.utc(2030, 3, 1, 9),
        isDemo: true,
      );

      expect(jsonDecode(requests.first.body), {
        'id': _userId,
        'display_name': 'Anna',
        'avatar_url': null,
        'is_demo': true,
      });
    });

    test('with the checkbox only saves only the notice', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 201));

      await SupabaseAccountRepository(client).saveFirstAccess(
        userId: _userId,
        noticeVersion: 'p1',
        readAt: DateTime.utc(2030, 3, 1, 9),
      );

      expect(requests.single.url.path, '/rest/v1/user_settings');
    });

    test('deletes the demo account with its function', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => http.Response('', 204));

      await SupabaseAccountRepository(client).deleteDemoAccount();

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/delete_my_demo_account');
    });

    test('throws when the deletion is refused', () async {
      final client = _client(
        [],
        (_) async => _json({'code': 'P0001', 'message': 'not_demo'}, 400),
      );

      await expectLater(
        SupabaseAccountRepository(client).deleteDemoAccount(),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('household', () {
    test('creates it with its function, with the id of the device', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => _json(_householdId));

      await SupabaseHouseholdRepository(client).createHousehold(
        id: _householdId,
        name: 'Casa di prova',
        startDate: DateTime(2031, 3, 15),
        cashOpeningCents: 1250,
      );

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/create_household');
      expect(jsonDecode(request.body), {
        'id': _householdId,
        'name': 'Casa di prova',
        'start_date': '2031-03-15',
        'cash_opening_cents': 1250,
      });
    });

    test('sends no cash as null', () async {
      final requests = <http.Request>[];
      final client = _client(requests, (_) async => _json(_householdId));

      await SupabaseHouseholdRepository(client).createHousehold(
        id: _householdId,
        name: 'Casa di prova',
        startDate: DateTime(2031, 3),
      );

      expect(
        jsonDecode(requests.single.body),
        containsPair('cash_opening_cents', null),
      );
    });

    test('throws the key of the error of the function', () async {
      final client = _client(
        [],
        (_) async =>
            _json({'code': 'P0001', 'message': 'start_date_out_of_range'}, 400),
      );

      Object? thrown;
      try {
        await SupabaseHouseholdRepository(client).createHousehold(
          id: _householdId,
          name: 'Casa di prova',
          startDate: DateTime(2031, 3),
        );
      } on Object catch (error) {
        thrown = error;
      }
      expect(
        CreateHouseholdError.of(thrown!),
        CreateHouseholdError.startDateOutOfRange,
      );
    });
  });
}
