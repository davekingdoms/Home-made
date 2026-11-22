import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/device/device_registry.dart';

import 'helpers/fakes.dart';

const _annaId = 'user-anna';
const _brunoId = 'user-bruno';

/// The registry with fakes around it, a clock that tests move and ids
/// numbered in order.
class _Harness {
  final devices = FakeDeviceRepository();
  final store = MemoryLocalStore();
  DateTime now = DateTime(2030, 3, 1, 9);
  int _ids = 0;

  late final registry = DeviceRegistry(
    remote: devices,
    store: store,
    newId: () => 'device-${++_ids}',
    now: () => now,
  );

  DeviceIdentity? get saved {
    final value = store.values[DeviceRegistry.storeKey];
    return value == null ? null : DeviceIdentity.fromJson(jsonDecode(value));
  }
}

void main() {
  group('the first entry of an account', () {
    test('creates the id on the device and inserts the row', () async {
      final harness = _Harness();

      await harness.registry.sync(_annaId);

      expect(harness.devices.rows, {'device-1': _annaId});
      expect(harness.saved?.id, 'device-1');
      expect(harness.saved?.userId, _annaId);
      expect(harness.saved?.registered, isTrue);
    });

    test('the second does not insert it again', () async {
      final harness = _Harness();
      await harness.registry.sync(_annaId);

      await harness.registry.sync(_annaId);

      expect(harness.devices.inserts, 1);
      expect(harness.devices.rows, hasLength(1));
    });

    test('two at once insert the row once', () async {
      final harness = _Harness();

      await Future.wait([
        harness.registry.sync(_annaId),
        harness.registry.sync(_annaId),
      ]);

      expect(harness.devices.inserts, 1);
    });

    test('without a network keeps the id and tries again later', () async {
      final harness = _Harness()..devices.error = offline;

      await harness.registry.sync(_annaId);
      expect(harness.saved?.id, 'device-1');
      expect(harness.saved?.registered, isFalse);

      harness.devices.error = null;
      await harness.registry.sync(_annaId);
      expect(harness.devices.rows, {'device-1': _annaId});
      expect(harness.saved?.registered, isTrue);
    });

    test('of another account on this installation gets its own id', () async {
      final harness = _Harness();
      await harness.registry.sync(_annaId);

      await harness.registry.sync(_brunoId);

      expect(harness.devices.rows, {'device-1': _annaId, 'device-2': _brunoId});
      expect(harness.saved?.userId, _brunoId);
    });
  });

  group('last_seen_at', () {
    test('moves at most once a day', () async {
      final harness = _Harness();
      await harness.registry.sync(_annaId);

      // Same day: the insert already set it.
      harness.now = DateTime(2030, 3, 1, 22);
      await harness.registry.sync(_annaId);
      expect(harness.devices.touches, isEmpty);

      harness.now = DateTime(2030, 3, 2, 8);
      await harness.registry.sync(_annaId);
      await harness.registry.sync(_annaId);
      expect(harness.devices.touches, ['device-1']);
      expect(harness.saved?.lastSeenOn, '2030-03-02');
    });
  });

  group('forget', () {
    test(
      'deletes the row and the local id, keeping the other values',
      () async {
        final harness = _Harness();
        await harness.registry.sync(_annaId);
        harness.store.values['device.location'] = 'kept';

        await harness.registry.forget();

        expect(harness.devices.rows, isEmpty);
        expect(harness.store.values, {'device.location': 'kept'});
        expect(await harness.registry.identity(), isNull);
      },
    );

    test('removes the local id also without a network', () async {
      final harness = _Harness();
      await harness.registry.sync(_annaId);
      harness.devices.error = offline;

      await harness.registry.forget();

      expect(harness.saved, isNull);
    });

    test('after it, the next entry is a new device', () async {
      final harness = _Harness();
      await harness.registry.sync(_annaId);
      await harness.registry.forget();

      await harness.registry.sync(_annaId);

      expect(harness.devices.rows, {'device-2': _annaId});
    });
  });

  test('an unreadable saved identity counts as none', () async {
    final harness = _Harness();
    harness.store.values[DeviceRegistry.storeKey] = 'not json';

    expect(await harness.registry.identity(), isNull);
    await harness.registry.sync(_annaId);
    expect(harness.devices.rows, {'device-1': _annaId});
  });
}
