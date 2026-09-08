import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/network/api_client.dart';

/// A dev build wrote a live account's password into the device log on
/// 2026-09-08, because the pretty logger prints request bodies verbatim and
/// the login payload carries one. These pin the masking that replaced it.
void main() {
  Object? redact(Object? v) => debugRedactForTest(v);

  group('credential fields are masked', () {
    test('a login body keeps the identifier and loses the password', () {
      final out = redact({'mobile': '+201200348131', 'password': 'hunter2'})
          as Map<Object?, Object?>;
      expect(out['mobile'], '+201200348131',
          reason: 'the identifier is what makes a log line useful');
      expect(out['password'], '<redacted>');
    });

    test('every known secret key is masked', () {
      const keys = [
        'password',
        'current_password',
        'new_password',
        'confirm_password',
        'password_confirmation',
        'old_password',
        'pin',
        'otp',
        'code',
        'token',
        'access_token',
        'refresh_token',
        'id_token',
        'secret',
        'client_secret',
      ];
      for (final k in keys) {
        final out = redact({k: 'SECRET-VALUE'}) as Map<Object?, Object?>;
        expect(out[k], '<redacted>', reason: k);
      }
    });

    test('matching is case-insensitive', () {
      final out =
          redact({'Password': 'x', 'OTP': 'y'}) as Map<Object?, Object?>;
      expect(out['Password'], '<redacted>');
      expect(out['OTP'], '<redacted>');
    });

    test('nested and listed secrets are reached', () {
      final out = redact({
        'user': {
          'profile': {'password': 'x'},
        },
        'batch': [
          {'otp': 'y'},
        ],
      }) as Map<Object?, Object?>;
      final user = out['user'] as Map<Object?, Object?>;
      final profile = user['profile'] as Map<Object?, Object?>;
      expect(profile['password'], '<redacted>');
      final batch = out['batch'] as List<Object?>;
      expect((batch.first as Map<Object?, Object?>)['otp'], '<redacted>');
    });

    test('a whole-key match, so ordinary metadata survives', () {
      // Substring matching would mask these, and they are not secrets — they
      // are exactly what you want to see when debugging an auth problem.
      final out = redact({
        'password_updated_at': '2026-09-01',
        'token_expires_in': 3600,
        'has_password': true,
      }) as Map<Object?, Object?>;
      expect(out['password_updated_at'], '2026-09-01');
      expect(out['token_expires_in'], 3600);
      expect(out['has_password'], true);
    });

    test('non-map payloads pass through untouched', () {
      expect(redact('plain string'), 'plain string');
      expect(redact(42), 42);
      expect(redact(null), isNull);
    });
  });
}
