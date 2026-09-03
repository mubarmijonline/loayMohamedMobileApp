import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/error/failures.dart';
import '../../../core/providers.dart';
import '../../providers.dart' as student_providers;
import '../data/auth_repository.dart';
import '../data/social_auth_service.dart';
import '../domain/student_user.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends Equatable {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.loading = false,
  });

  final AuthStatus status;
  final StudentUser? user;
  final AppFailure? error;
  final bool loading;

  AuthState copyWith({
    AuthStatus? status,
    StudentUser? user,
    AppFailure? error,
    bool? loading,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        error: clearError ? null : (error ?? this.error),
        loading: loading ?? this.loading,
      );

  static const initial = AuthState(status: AuthStatus.unknown);

  @override
  List<Object?> get props => [status, user, error, loading];
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.read(apiClientProvider), ref.read(tokenStoreProvider)),
);

final socialAuthServiceProvider =
    Provider<SocialAuthService>((ref) => SocialAuthService());

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref));

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(AuthState.initial);
  final Ref _ref;

  static const _kCachedUser = 'auth.cached_user';

  /// Invalidate every student-scoped data provider so the next read fetches
  /// fresh data for the newly-active user. Called after login, social login,
  /// register and logout so screens never show stale data from a previous
  /// session.
  void _invalidateStudentData() {
    _ref
      ..invalidate(student_providers.dashboardProvider)
      ..invalidate(student_providers.subjectsProvider)
      ..invalidate(student_providers.enrolledSubjectsProvider)
      ..invalidate(student_providers.enrollmentsProvider)
      ..invalidate(student_providers.quizzesProvider)
      ..invalidate(student_providers.subjectWorkloadProvider)
      ..invalidate(student_providers.contentsProvider)
      // Per-content families: clear so the next user never inherits the
      // previous user's resume position / embed ticket on this device.
      ..invalidate(student_providers.contentProvider)
      ..invalidate(student_providers.contentEmbedProvider)
      ..invalidate(student_providers.contentResumeProvider);
  }

  Future<void> bootstrap() async {
    final tokens = await _ref.read(tokenStoreProvider).read();
    final cache = _ref.read(kvCacheProvider);
    if (tokens == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      return;
    }
    final cached = cache.readJson<StudentUser>(
      _kCachedUser,
      (j) => StudentUser.fromJson(Map<String, dynamic>.from(j as Map)),
    );
    if (cached != null) {
      state = AuthState(status: AuthStatus.authenticated, user: cached);
    }
    try {
      final user = await _ref.read(authRepositoryProvider).me();
      await cache.putJson(_kCachedUser, user.toJson());
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on AppFailure catch (e) {
      // RoleFailure is no longer thrown by me() — keep UnauthorizedFailure
      // handling only so parents are not logged out on bootstrap.
      if (e is UnauthorizedFailure) {
        await _ref.read(tokenStoreProvider).clear();
        await cache.remove(_kCachedUser);
        state = AuthState(status: AuthStatus.unauthenticated, error: e);
      } else if (cached == null) {
        state = AuthState(status: AuthStatus.unauthenticated, error: e);
      }
    }
  }

  Future<bool> login({required String identifier, required String password, bool rememberMe = true}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(authRepositoryProvider).login(identifier: identifier, password: password);
      if (rememberMe) {
        await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
      }
      _invalidateStudentData();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e, st) {
      state = state.copyWith(loading: false, error: ErrorMapper.fromObject(e, st));
      return false;
    }
  }

  Future<ParentOtpRequest?> requestParentOtp({required String phone}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _ref
          .read(authRepositoryProvider)
          .requestParentOtp(phone: phone);
      state = state.copyWith(loading: false);
      return res;
    } catch (e, st) {
      state =
          state.copyWith(loading: false, error: ErrorMapper.fromObject(e, st));
      return null;
    }
  }

  Future<bool> verifyParentOtp({
    required String phone,
    required String code,
    bool rememberMe = true,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref.read(authRepositoryProvider).verifyParentOtp(
            phone: phone,
            code: code,
          );
      if (rememberMe) {
        await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
      }
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e, st) {
      state = state.copyWith(loading: false, error: ErrorMapper.fromObject(e, st));
      return false;
    }
  }

  Future<bool> createStudentUser({
    required String name,
    required String email,
    required String phone,
    required String countryCode,
    required String parentPhone,
    required String parentCountryCode,
    required String school,
    required int grade,
    required String password,
    bool rememberMe = true,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user =
          await _ref.read(authRepositoryProvider).createStudentUser(
                name: name,
                email: email,
                phone: phone,
                countryCode: countryCode,
                parentPhone: parentPhone,
                parentCountryCode: parentCountryCode,
                school: school,
                grade: grade,
                password: password,
              );
      // If register returned tokens + user, we're already authenticated.
      final tokens = await _ref.read(tokenStoreProvider).read();
      if (tokens != null && user.id.isNotEmpty) {
        if (rememberMe) {
          await _ref
              .read(kvCacheProvider)
              .putJson(_kCachedUser, user.toJson());
        }
        _invalidateStudentData();
        state = AuthState(status: AuthStatus.authenticated, user: user);
        return true;
      }
      // Otherwise fall back to logging in.
      return await login(
        identifier: email,
        password: password,
        rememberMe: rememberMe,
      );
    } catch (e, st) {
      state = state.copyWith(
          loading: false, error: ErrorMapper.fromObject(e, st),);
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(loading: true);
    await _ref.read(authRepositoryProvider).logout();
    await _ref.read(socialAuthServiceProvider).signOutAll();
    await _ref.read(kvCacheProvider).remove(_kCachedUser);
    _invalidateStudentData();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> _socialLogin(SocialCredential cred,
      {bool rememberMe = true,}) async {
    try {
      final user = await _ref.read(authRepositoryProvider).socialLogin(
            provider: cred.provider,
            idToken: cred.idToken,
            authorizationCode: cred.authorizationCode,
            email: cred.email,
            name: cred.name,
            nonce: cred.nonce,
          );
      if (rememberMe) {
        await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
      }
      _invalidateStudentData();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e, st) {
      state = state.copyWith(
        loading: false,
        error: ErrorMapper.fromObject(e, st),
      );
      return false;
    }
  }

  Future<bool> loginWithApple({bool rememberMe = true}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final cred =
          await _ref.read(socialAuthServiceProvider).signInWithApple();
      return await _socialLogin(cred, rememberMe: rememberMe);
    } catch (e, st) {
      state = state.copyWith(
        loading: false,
        error: ErrorMapper.fromObject(e, st),
      );
      return false;
    }
  }

  Future<bool> loginWithGoogle({bool rememberMe = true}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final cred =
          await _ref.read(socialAuthServiceProvider).signInWithGoogle();
      return await _socialLogin(cred, rememberMe: rememberMe);
    } catch (e, st) {
      state = state.copyWith(
        loading: false,
        error: ErrorMapper.fromObject(e, st),
      );
      return false;
    }
  }

  Future<void> forceLogout({String? reason, String? message}) async {
    await _ref.read(tokenStoreProvider).clear();
    await _ref.read(kvCacheProvider).remove(_kCachedUser);
    _invalidateStudentData();
    AppFailure failure;
    switch (reason) {
      case 'account_blocked':
        failure = AccountBlockedFailure(
          message ??
              'Your account has been blocked. Please contact support.',
        );
        break;
      case 'session_revoked':
        failure = SessionRevokedFailure(
          message ?? 'You have been signed out. Please sign in again.',
        );
        break;
      default:
        failure = UnauthorizedFailure(message ?? 'Session expired. Please sign in again.');
    }
    state = AuthState(
      status: AuthStatus.unauthenticated,
      error: failure,
    );
  }

  Future<void> refreshMe() async {
    try {
      final user = await _ref.read(authRepositoryProvider).me();
      await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
      state = state.copyWith(user: user, status: AuthStatus.authenticated);
    } catch (_) {
      // Keep previous state on transient failures.
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}
