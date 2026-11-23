import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'local_store.g.dart';

/// Small values of this installation, kept on the device: its id, the
/// startup state of each account and, from the next iterations, the values
/// the device asks only once (location, pending invite, unlock time).
///
/// Never data of the finances: their cache is a database of its own.
abstract interface class LocalStore {
  /// The value saved under [key], or null.
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  /// Removes [key]; nothing happens when it is not there.
  Future<void> remove(String key);
}

/// [LocalStore] on the asynchronous API of `shared_preferences`.
class SharedPreferencesLocalStore implements LocalStore {
  new() : _preferences = SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

/// The store of the app. `main` overrides it; tests use one in memory.
@Riverpod(keepAlive: true)
LocalStore localStore(Ref ref) =>
    throw StateError('localStoreProvider must be overridden at startup');
