import 'dart:async';
import 'dart:io';

import 'package:homemade/core/storage/local_store.dart';
import 'package:homemade/features/auth/device_lock.dart';
import 'package:homemade/features/device/device_repository.dart';
import 'package:homemade/features/startup/account_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An account that has done every step.
const readyAccount = AccountStatus(
  hasProfile: true,
  noticeVersion: privacyNoticeVersion,
  hasMember: true,
);

/// An account at its first access: no profile, no notice read.
const newAccount = AccountStatus(
  hasProfile: false,
  noticeVersion: null,
  hasMember: false,
);

/// A demo account that has done every step.
const demoAccount = AccountStatus(
  hasProfile: true,
  noticeVersion: privacyNoticeVersion,
  hasMember: true,
  isDemo: true,
);

/// An account with its profile and an older notice.
const oldNoticeAccount = AccountStatus(
  hasProfile: true,
  noticeVersion: 'p0',
  hasMember: true,
);

/// A request that never got an answer.
const offline = SocketException('no network');

/// An answer of Supabase with an error.
const serverError = PostgrestException(message: 'refused', code: '42501');

/// [LocalStore] in memory.
class MemoryLocalStore implements LocalStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}

/// A save of the first access, as [FakeAccountRepository] received it.
typedef FirstAccessSave = ({
  String userId,
  String? displayName,
  String? avatarUrl,
  String noticeVersion,
  bool isDemo,
});

/// [AccountRepository] in memory.
class FakeAccountRepository implements AccountRepository {
  new({this.status = readyAccount});

  /// What [readStatus] returns.
  AccountStatus status;

  /// When set, [readStatus] throws it.
  Exception? readError;

  /// When set, [readStatus] waits for it.
  Completer<void>? readGate;

  /// When set, [saveFirstAccess] throws it.
  Exception? saveError;

  /// When set, [saveFirstAccess] waits for it.
  Completer<void>? saveGate;

  /// When set, [deleteDemoAccount] throws it.
  Exception? deleteError;

  int reads = 0;
  int deletions = 0;
  final saves = <FirstAccessSave>[];

  @override
  Future<AccountStatus> readStatus(String userId) async {
    reads++;
    await readGate?.future;
    final error = readError;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<void> saveFirstAccess({
    required String userId,
    required String noticeVersion,
    required DateTime readAt,
    String? displayName,
    String? avatarUrl,
    bool isDemo = false,
  }) async {
    await saveGate?.future;
    final error = saveError;
    if (error != null) throw error;
    saves.add((
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      noticeVersion: noticeVersion,
      isDemo: isDemo,
    ));
  }

  @override
  Future<void> deleteDemoAccount() async {
    final error = deleteError;
    if (error != null) throw error;
    deletions++;
  }
}

/// [DeviceRepository] in memory: the rows of `devices`, by id.
class FakeDeviceRepository implements DeviceRepository {
  /// User of each row, by device id.
  final rows = <String, String>{};

  /// Devices whose `last_seen_at` moved, in order.
  final touches = <String>[];

  int inserts = 0;

  /// When set, every call throws it.
  Exception? error;

  /// When set, [insert] waits for it.
  Completer<void>? insertGate;

  @override
  Future<void> insert({
    required String id,
    required String userId,
    required String platform,
  }) async {
    inserts++;
    await insertGate?.future;
    final error = this.error;
    if (error != null) throw error;
    rows[id] = userId;
  }

  @override
  Future<void> touch(String id, DateTime at) async {
    final error = this.error;
    if (error != null) throw error;
    touches.add(id);
  }

  @override
  Future<void> delete(String id) async {
    final error = this.error;
    if (error != null) throw error;
    rows.remove(id);
  }
}

/// [DeviceLock] in memory. A request stays open until [answer].
class FakeDeviceLock implements DeviceLock {
  new({this.secure = false});

  /// Whether the device has a secure screen lock.
  bool secure;

  /// When set, [isSecure] waits for it.
  Completer<void>? checkGate;

  /// Calls to [isSecure] and to [unlock].
  int checks = 0;
  int requests = 0;

  Completer<UnlockResult>? _open;

  /// Whether a request of the system is open.
  bool get requestOpen => _open != null;

  @override
  Future<bool> isSecure() async {
    checks++;
    await checkGate?.future;
    return secure;
  }

  @override
  Future<UnlockResult> unlock() {
    requests++;
    final open = Completer<UnlockResult>();
    _open = open;
    return open.future;
  }

  /// Ends the open request with [result].
  void answer(UnlockResult result) {
    final open = _open;
    if (open == null) throw StateError('no request is open');
    _open = null;
    open.complete(result);
  }
}

/// A monotonic clock the tests move by hand.
class FakeClock {
  Duration now = Duration.zero;

  Duration call() => now;

  void advance(Duration duration) => now += duration;
}
