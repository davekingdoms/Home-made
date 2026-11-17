import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:homemade/features/auth/auth_repository.dart';
import 'package:homemade/features/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('a failure of the Google account picker', () {
    test('is a cancellation when the user closes it', () {
      expect(
        signInResultFromGoogle(GoogleSignInExceptionCode.canceled),
        SignInResult.cancelled,
      );
    });

    test('is a configuration error for the client and the provider', () {
      const codes = [
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
      ];
      for (final code in codes) {
        expect(
          signInResultFromGoogle(code),
          SignInResult.configurationError,
          reason: code.name,
        );
      }
    });

    test('is a generic failure for every other code', () {
      const codes = [
        GoogleSignInExceptionCode.interrupted,
        GoogleSignInExceptionCode.uiUnavailable,
        GoogleSignInExceptionCode.userMismatch,
        GoogleSignInExceptionCode.unknownError,
      ];
      for (final code in codes) {
        expect(
          signInResultFromGoogle(code),
          SignInResult.failed,
          reason: code.name,
        );
      }
    });
  });

  group('a failure of Supabase', () {
    test('is a network error when the request gets no answer', () {
      expect(
        signInResultFromSupabase(AuthRetryableFetchException()),
        SignInResult.networkError,
      );
    });

    test('is a refusal when Supabase answers with an error', () {
      expect(
        signInResultFromSupabase(
          const AuthException('refused', statusCode: '400', code: 'bad_jwt'),
        ),
        SignInResult.rejected,
      );
    });
  });
}
