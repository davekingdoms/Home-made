import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:homemade/core/remote/remote_failure.dart';
import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/features/device/device_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'device_registry.g.dart';

/// Platform written in `devices`: the app is built for Android only.
const devicePlatform = 'android';

/// This installation as a device of one account: the id generated here and
/// whether its row in `devices` is saved.
@immutable
class DeviceIdentity {
  const new({
    required this.id,
    required this.userId,
    this.registered = false,
    this.lastSeenOn,
  });

  /// Reads what [toJson] wrote; null when [json] is not an identity.
  static DeviceIdentity? fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'userId': final String userId,
      'registered': final bool registered,
      'lastSeenOn': final String? lastSeenOn,
    }) {
      return DeviceIdentity(
        id: id,
        userId: userId,
        registered: registered,
        lastSeenOn: lastSeenOn,
      );
    }
    return null;
  }

  /// Id of the row in `devices`, generated on the device.
  final String id;

  /// The account the device is registered with.
  final String userId;

  /// Whether the row is saved on the server.
  final bool registered;

  /// Local day (`yyyy-mm-dd`) of the last `last_seen_at` sent.
  final String? lastSeenOn;

  DeviceIdentity copyWith({bool? registered, String? lastSeenOn}) =>
      DeviceIdentity(
        id: id,
        userId: userId,
        registered: registered ?? this.registered,
        lastSeenOn: lastSeenOn ?? this.lastSeenOn,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'registered': registered,
    'lastSeenOn': lastSeenOn,
  };
}

/// Registers this installation in `devices` (`docs/spec/accesso.md`,
/// section 1).
///
/// The first time an account enters on this installation the device gets a
/// new id, saved in the [LocalStore] with the id of the account, and its row;
/// after that `last_seen_at` moves at most once a day. "Esci" deletes the row
/// and the local id. The other values of the device stay.
///
/// Nothing here throws, and the logs carry only the step and the code: never
/// ids or models.
class DeviceRegistry {
  new({
    required this._remote,
    required this._store,
    String Function()? newId,
    DateTime Function()? now,
  }) : _newId = newId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  /// Key of the identity in the [LocalStore].
  static const storeKey = 'device.identity';

  /// Longest wait on "Esci", both for a sync still running and for the
  /// deletion of the row.
  static const forgetTimeout = Duration(seconds: 3);

  final DeviceRepository _remote;
  final LocalStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  /// The sync running, if any: the next caller waits for it.
  Future<void>? _running;

  /// Grows at every [forget]: a sync that started before it saves nothing,
  /// so a late answer cannot bring the forgotten id back.
  int _epoch = 0;

  /// The identity saved on this installation, or null.
  Future<DeviceIdentity?> identity() async {
    final saved = await _store.read(storeKey);
    if (saved == null) return null;
    try {
      return DeviceIdentity.fromJson(jsonDecode(saved));
    } on FormatException {
      return null;
    }
  }

  /// Registers the device for [userId] if it is not yet, otherwise sends
  /// `last_seen_at` if today it has not been sent. Called when the account
  /// enters and when the app comes back to the foreground.
  Future<void> sync(String userId) {
    final running = _running;
    if (running != null) return running;
    late final Future<void> started;
    started = _sync(userId).whenComplete(() {
      if (identical(_running, started)) _running = null;
    });
    return _running = started;
  }

  /// Deletes the row of the device and its local id. A sync still running
  /// and the deletion each wait at most [forgetTimeout]: on a slow network
  /// or without one the local id goes anyway.
  Future<void> forget() async {
    _epoch++;
    final running = _running;
    if (running != null) {
      try {
        await running.timeout(forgetTimeout);
      } on TimeoutException catch (error) {
        // Left behind: it saves nothing, and the next sync starts afresh.
        _log('wait for sync', error);
        if (identical(_running, running)) _running = null;
      }
    }
    final identity = await this.identity();
    if (identity == null) return;
    try {
      await _remote.delete(identity.id).timeout(forgetTimeout);
    } on Object catch (error) {
      _log('delete', error);
    }
    await _store.remove(storeKey);
  }

  Future<void> _sync(String userId) async {
    final epoch = _epoch;
    Future<void> save(DeviceIdentity identity) async {
      if (epoch == _epoch) await _save(identity);
    }

    try {
      var identity = await this.identity();
      if (identity == null || identity.userId != userId) {
        identity = DeviceIdentity(id: _newId(), userId: userId);
        await save(identity);
      }
      final today = _day(_now());
      if (!identity.registered) {
        await _remote.insert(
          id: identity.id,
          userId: userId,
          platform: devicePlatform,
        );
        // The new row has last_seen_at = now().
        await save(identity.copyWith(registered: true, lastSeenOn: today));
      } else if (identity.lastSeenOn != today) {
        await _remote.touch(identity.id, _now());
        await save(identity.copyWith(lastSeenOn: today));
      }
    } on Object catch (error) {
      // Tried again at the next start or return to the foreground.
      _log('sync', error);
    }
  }

  Future<void> _save(DeviceIdentity identity) =>
      _store.write(storeKey, jsonEncode(identity.toJson()));

  static String _day(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  static void _log(String step, Object error) => developer.log(
    'device $step failed: ${remoteErrorCode(error)}',
    name: 'device',
  );
}

/// The registry of the app.
@Riverpod(keepAlive: true)
DeviceRegistry deviceRegistry(Ref ref) => DeviceRegistry(
  remote: ref.watch(deviceRepositoryProvider),
  store: ref.watch(localStoreProvider),
);
