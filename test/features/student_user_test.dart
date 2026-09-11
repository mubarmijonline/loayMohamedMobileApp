import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/auth/domain/student_user.dart';

/// `has_password` decides how account deletion asks for confirmation, and a
/// mistake either way is a store rejection: a password prompt for an account
/// with no password makes deletion impossible.
void main() {
  StudentUser parse(Map<String, dynamic> extra) => StudentUser.fromJson({
        '_id': 'u1',
        'name': 'Omar Student',
        'email': 'omar@example.com',
        'role': 'student',
        ...extra,
      });

  group('hasPassword', () {
    test('reads has_password from /auth/me', () {
      expect(parse({'has_password': true}).hasPassword, isTrue);
      expect(parse({'has_password': false}).hasPassword, isFalse);
    });

    test('defaults to true when the field is absent', () {
      // A user cached before this field existed has no key. Asking for a
      // password is the safe default; the next /auth/me refresh corrects it.
      expect(parse({}).hasPassword, isTrue);
    });

    test('survives the cache round trip', () {
      // The user is cached with toJson and restored with fromJson at launch.
      final u = parse({'has_password': false});
      expect(StudentUser.fromJson(u.toJson()).hasPassword, isFalse);
    });

    test('survives copyWith', () {
      // copyWith rebuilds the object from scratch, so a field it forgets to
      // pass silently falls back to its default.
      final u = parse({'has_password': false});
      expect(u.copyWith(name: 'Renamed').hasPassword, isFalse);
    });
  });
}
