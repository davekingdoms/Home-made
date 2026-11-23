import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_repository.g.dart';

/// The rows of `devices` that belong to the signed-in user.
abstract interface class DeviceRepository {
  /// Inserts the device [id] of [userId] on [platform].
  ///
  /// It completes normally also when the row is already there (a second
  /// insert with the same id is a `23505`), and throws on any other failure.
  Future<void> insert({
    required String id,
    required String userId,
    required String platform,
  });

  /// Sets `last_seen_at` of the device [id] to [at].
  Future<void> touch(String id, DateTime at);

  /// Deletes the device [id]; nothing happens when it is not there.
  Future<void> delete(String id);
}

/// The repository of the app. `main` overrides it; tests use a fake.
@Riverpod(keepAlive: true)
DeviceRepository deviceRepository(Ref ref) =>
    throw StateError('deviceRepositoryProvider must be overridden at startup');
