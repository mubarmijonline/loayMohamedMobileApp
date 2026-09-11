import 'package:dio/dio.dart';

import '../../../core/env/app_env.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/failures.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/storage/secure_token_store.dart';
import '../domain/student_user.dart';

class AuthRepository {
  AuthRepository(this._client, this._tokens);

  final ApiClient _client;
  final SecureTokenStore _tokens;

  String get _v1 => AppEnv.I.apiV1Prefix;

  Future<StudentUser> login({
    required String identifier,
    required String password,
    String? deviceId,
  }) async {
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/auth/login',
        data: {
          'identifier': identifier,
          'password': password,
          if (deviceId != null) 'device_id': deviceId,
        },
        options: Options(extra: const {'skipAuth': true}),
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw ValidationFailure(env.errorMessage ?? 'Invalid credentials');
      }
      final data = env.data!;
      final bundle = TokenBundle.fromAuthPayload(data);
      if (bundle == null) {
        throw const ServerFailure('Auth response missing tokens.');
      }
      await _tokens.save(bundle);
      final userJson = (data['user'] ?? data['student']) as Map?;
      if (userJson == null) {
        return await me();
      }
      final user = StudentUser.fromJson(Map<String, dynamic>.from(userJson));
      if (!user.isStudent) {
        await _tokens.clear();
        throw const RoleFailure();
      }
      return user;
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<StudentUser> me() async {
    try {
      final res = await _client.dio.get<dynamic>('$_v1/auth/me');
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw const UnauthorizedFailure();
      }
      return StudentUser.fromJson(env.data!);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Step 1 of parent passwordless login.
  ///
  /// Backend contract — `POST /auth/parent/otp/request`:
  ///   request:  { phone: '+201234567890' }
  ///   success:  { success: true, data: {
  ///                 otp_sent: true,
  ///                 expires_in: 300,        // seconds the code is valid
  ///                 resend_after: 60,       // seconds before user may resend
  ///                 linked_students: int    // count for UX hint (optional)
  ///              } }
  ///   not linked: 404 { success:false, error:{ code:'parent_not_linked',
  ///                                            message:'This number is not
  ///                                            linked to any student.' } }
  ///   rate limited: 429 { error:{ code:'otp_rate_limited',
  ///                               message:'Try again in N seconds.' } }
  ///
  /// Does NOT require auth — `skipAuth: true`.
  Future<ParentOtpRequest> requestParentOtp({required String phone}) async {
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/auth/parent/otp/request',
        data: {'phone': phone},
        options: Options(extra: const {'skipAuth': true}),
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success) {
        throw ValidationFailure(env.errorMessage ?? 'Could not send code');
      }
      final data = env.data ?? const <String, dynamic>{};
      return ParentOtpRequest(
        expiresIn: (data['expires_in'] as num?)?.toInt() ?? 300,
        resendAfter: (data['resend_after'] as num?)?.toInt() ?? 60,
        linkedStudents: (data['linked_students'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Step 2 of parent passwordless login.
  ///
  /// Backend contract — `POST /auth/parent/otp/verify`:
  ///   request:  { phone: '+201234567890', code: '123456',
  ///               device_id?: '...' }
  ///   success:  { success: true, data: {
  ///                 user: { id, role:'parent', name, phone, avatar_url, ... },
  ///                 access_token, refresh_token, expires_in,
  ///                 linked_students: [ { id, name, grade, avatar_url } ]
  ///              } }
  ///   bad code: 401 { error:{ code:'otp_invalid' | 'otp_expired',
  ///                           message:'...' } }
  ///   too many tries: 429 { error:{ code:'otp_too_many_attempts' } }
  Future<StudentUser> verifyParentOtp({
    required String phone,
    required String code,
    String? deviceId,
  }) async {
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/auth/parent/otp/verify',
        data: {
          'phone': phone,
          'code': code,
          if (deviceId != null) 'device_id': deviceId,
        },
        options: Options(extra: const {'skipAuth': true}),
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw ValidationFailure(env.errorMessage ?? 'Invalid code');
      }
      final data = env.data!;
      final bundle = TokenBundle.fromAuthPayload(data);
      if (bundle == null) {
        throw const ServerFailure('Auth response missing tokens.');
      }
      await _tokens.save(bundle);
      final userJson = (data['user']) as Map?;
      if (userJson == null) return await me();
      // Merge top-level linked_students into the user map so StudentUser.fromJson
      // can parse them in one pass.
      final mergedJson = <String, dynamic>{
        ...Map<String, dynamic>.from(userJson),
        if (data['linked_students'] != null)
          'linked_students': data['linked_students'],
      };
      final user = StudentUser.fromJson(mergedJson);
      if (!user.isParent) {
        await _tokens.clear();
        throw const RoleFailure('This account is not a parent account.');
      }
      return user;
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<void> logout() async {
    try {
      await _client.dio.post<dynamic>('$_v1/auth/logout');
    } on DioException {
      // Best-effort — proceed with local clear regardless.
    } finally {
      await _tokens.clear();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    String? confirmPassword,
  }) async {
    try {
      await _client.dio.post<dynamic>(
        '$_v1/student/profile/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': confirmPassword ?? newPassword,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// `POST /auth/account/delete` — permanently deletes the signed-in account.
  ///
  /// Not deployed yet; the contract is docs/mobile/BACKEND_ACCOUNT_DELETION.md.
  /// Sends `password` for accounts that have one, and `confirm: "DELETE"` for
  /// the legacy social-login accounts that never set a password.
  ///
  /// Clears tokens only after the server confirms, mirroring [logout]. On a
  /// refusal — a wrong password, usually — it throws and changes nothing.
  Future<void> deleteAccount({String? password, String? confirmPhrase}) async {
    try {
      await _client.dio.post<dynamic>(
        '$_v1/auth/account/delete',
        data: {
          if (password != null) 'password': password,
          if (confirmPhrase != null) 'confirm': confirmPhrase,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
    await _tokens.clear();
  }

  /// `PATCH /student/profile/phone` — `{ phone, country_code? }`.
  /// Changing the phone resets `phone_verified` to false server-side.
  Future<void> changePhone(String phone, {String? countryCode}) async {
    try {
      await _client.dio.patch<dynamic>(
        '$_v1/student/profile/phone',
        data: {
          'phone': phone,
          if (countryCode != null) 'country_code': countryCode,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<StudentUser> createStudentUser({
    required String name,
    required String email,
    required String phone,
    required String countryCode,
    required String parentPhone,
    required String parentCountryCode,
    required String school,
    required int grade,
    required String password,
  }) async {
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/auth/register',
        data: {
          'full_name': name,
          'name': name, // backwards-compatible alias
          'email': email,
          'phone': phone,
          'country_code': countryCode,
          'parent_phone': parentPhone,
          'parent_country_code': parentCountryCode,
          'school': school,
          'grade': grade,
          'password': password,
          'role': 'student',
        },
        options: Options(extra: const {'skipAuth': true}),
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw ValidationFailure(env.errorMessage ?? 'Could not create user');
      }
      // Persist tokens if the backend returns them on register.
      final data = env.data!;
      final bundle = TokenBundle.fromAuthPayload(data);
      if (bundle != null) {
        await _tokens.save(bundle);
      }
      final userJson = (data['user'] ?? data['student']) as Map?;
      if (userJson != null) {
        return StudentUser.fromJson(Map<String, dynamic>.from(userJson));
      }
      // Fallback: return a minimal user; caller can refresh via me().
      return StudentUser(
        id: '',
        name: name,
        email: email,
        role: 'student',
        phone: phone,
        parentPhone: parentPhone,
        school: school,
        grade: grade.toString(),
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<StudentUser> profile() async {
    try {
      final res = await _client.dio.get<dynamic>('$_v1/student/profile');
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw ValidationFailure(env.errorMessage ?? 'Could not load profile');
      }
      return StudentUser.fromJson(env.data!);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<StudentUser> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? countryCode,
    String? parentPhone,
    String? parentCountryCode,
    String? school,
    int? grade,
  }) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (name != null) 'full_name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (countryCode != null) 'country_code': countryCode,
        if (parentPhone != null) 'parent_phone': parentPhone,
        if (parentCountryCode != null) 'parent_country_code': parentCountryCode,
        if (school != null) 'school': school,
        if (grade != null) 'grade': grade,
      };
      final res =
          await _client.dio.patch<dynamic>('$_v1/student/profile', data: data);
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success) {
        throw ValidationFailure(env.errorMessage ?? 'Could not update profile');
      }
      if (env.data == null) {
        return profile();
      }
      return StudentUser.fromJson(env.data!);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<String> uploadProfileImage(String filePath) async {
    try {
      final form = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath),
      });
      final res = await _client.dio
          .post<dynamic>('$_v1/student/profile/avatar', data: form);
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        throw ValidationFailure(
          env.errorMessage ?? 'Could not upload profile image',
        );
      }
      final url = env.data!['avatar_url']?.toString() ??
          env.data!['avatar']?.toString() ??
          '';
      if (url.isEmpty) {
        throw const ServerFailure('Upload response missing avatar_url');
      }
      return url;
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }
}

/// Result of a successful `requestParentOtp` call.
class ParentOtpRequest {
  const ParentOtpRequest({
    required this.expiresIn,
    required this.resendAfter,
    required this.linkedStudents,
  });
  final int expiresIn;
  final int resendAfter;
  final int linkedStudents;
}
