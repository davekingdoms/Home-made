import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/features/auth/nonce.dart';

void main() {
  // Google receives the hash and Supabase the raw nonce: the hash must be
  // the SHA-256 of the raw value, in lowercase hexadecimal.
  test('the hash is the SHA-256 of the raw nonce, in lowercase hex', () {
    expect(
      hashNonce('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      hashNonce(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('a raw nonce is 32 random bytes in lowercase hex', () {
    final nonce = generateRawNonce();

    expect(nonce, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(generateRawNonce(), isNot(nonce));
  });
}
