import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Bytes of entropy in a raw nonce.
const _rawNonceBytes = 32;

/// A new raw nonce: 32 bytes from the secure random generator, in lowercase
/// hexadecimal.
///
/// It ties the ID token Google issues to this run of the app. It stays in
/// memory and is never logged.
String generateRawNonce() {
  final random = Random.secure();
  return [
    for (var i = 0; i < _rawNonceBytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// The SHA-256 of [rawNonce], in lowercase hexadecimal.
///
/// Google receives the hash and writes it in the ID token; Supabase receives
/// the raw nonce, hashes it the same way and compares the two.
String hashNonce(String rawNonce) =>
    sha256.convert(utf8.encode(rawNonce)).toString();
