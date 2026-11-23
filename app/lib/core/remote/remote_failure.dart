import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a request to Supabase failed, as the screens tell it.
enum RemoteFailure {
  /// No answer: no network, a timeout, a connection that dropped.
  connection,

  /// Supabase answered with an error.
  server;

  /// The failure behind [error], thrown by a request to Supabase.
  ///
  /// Supabase errors carry an answer; anything else (sockets, the HTTP
  /// client, timeouts) means the answer never arrived.
  static RemoteFailure of(Object error) => switch (error) {
    AuthRetryableFetchException() => connection,
    PostgrestException() || AuthException() => server,
    _ => connection,
  };
}

/// Code of [error] for the logs: the Postgres or HTTP code when Supabase
/// answered, otherwise the kind of failure. Never the message, which may
/// quote values.
String remoteErrorCode(Object error) => switch (error) {
  PostgrestException(:final code) => 'postgrest ${code ?? 'no code'}',
  AuthException(:final statusCode, :final code) =>
    'auth status $statusCode, code $code',
  TimeoutException() => 'timeout',
  SocketException() => 'socket',
  _ => 'no answer',
};
