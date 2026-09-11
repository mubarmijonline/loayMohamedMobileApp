import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/error/failures.dart';
import '../../../core/providers.dart';
import '../../notifications/push_service.dart';
import '../../providers.dart' as student_providers;
import '../data/auth_repository.dart';
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
  (ref) =>
      AuthRepository(ref.read(apiClientProvider), ref.read(tokenStoreProvider)),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

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

  /// Resolves the startup auth state.
  ///
  /// **Must always leave [state] in a definite status.** The app shows the
  /// splash for as long as the status is `unknown`, and this is called
  /// fire-and-forget from `LoayMohamedApp.initState` — so anything that
  /// escapes here strands the user on a spinner forever with no error and no
  /// way out.
  ///
  /// That is exactly what used to happen: the inner catch below only handled
  /// `AppFailure`, and a Keychain `PlatformException` from the token store
  /// (iOS -34018, missing entitlement) sailed straight past it. The outer
  /// catch is the backstop — signed out is recoverable, a frozen splash is
  /// not.
  Future<void> bootstrap() async {
    try {
      await _bootstrap();
    } catch (e, st) {
      AppLogger.I.e('Auth bootstrap failed, falling back to login: $e\n$st');
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: ErrorMapper.fromObject(e, st),
      );
    }
  }

  Future<void> _bootstrap() async {
    final tokens = await _ref.read(tokenStoreProvider).read();
    final cache = _ref.read(kvCacheProvider);
    if (tokens == null) {
      state =
          state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
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
    } catch (raw) {
      // me() maps Dio errors to AppFailure, but a platform/plugin error can
      // still surface here. Normalise so the branches below are total.
      final e = ErrorMapper.fromObject(raw);
      // RoleFailure is no longer thrown by me() — keep UnauthorizedFailure
      // handling only so parents are not logged out on bootstrap.
      if (e is UnauthorizedFailure) {
        await _ref.read(tokenStoreProvider).clear();
        await cache.remove(_kCachedUser);
        state = AuthState(status: AuthStatus.unauthenticated, error: e);
      } else if (cached == null) {
        state = AuthState(status: AuthStatus.unauthenticated, error: e);
      }
      // If a cached user exists we deliberately stay authenticated and let the
      // user work offline — but only because `state` was already set to
      // authenticated above, so the status is never left `unknown`.
      assert(
        state.status != AuthStatus.unknown,
        'bootstrap must resolve to a definite auth status',
      );
    }
  }

  Future<bool> login({
    required String identifier,
    required String password,
    bool rememberMe = true,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _ref
          .read(authRepositoryProvider)
          .login(identifier: identifier, password: password);
      if (rememberMe) {
        await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
      }
      _invalidateStudentData();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e, st) {
      state =
          state.copyWith(loading: false, error: ErrorMapper.fromObject(e, st));
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
      state =
          state.copyWith(loading: false, error: ErrorMapper.fromObject(e, st));
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
      final user = await _ref.read(authRepositoryProvider).createStudentUser(
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
          await _ref.read(kvCacheProvider).putJson(_kCachedUser, user.toJson());
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
        loading: false,
        error: ErrorMapper.fromObject(e, st),
      );
      return false;
    }
  }

  /// Signs the user out.
  ///
  /// ORDER MATTERS (API_BRIEF §4): the push device must be unregistered
  /// **before** `/auth/logout`, because logout bumps `token_version` and kills
  /// every token for this user — including the one `DELETE /devices/<id>`
  /// needs. Unregister after logout and the call 401s, leaving the device
  /// registered and still receiving push for an account that is signed out.
  ///
  /// Note also that logout is **global**: it signs the user out on every
  /// device, not just this one. There is no per-device logout. Callers should
  /// warn the user first (see [logoutWarning]).
  Future<void> logout() async {
    state = state.copyWith(loading: true);
    // 1. Drop the push device while the access token is still valid.
    await _ref.read(pushServiceProvider).unbind();
    // 2. Revoke the session server-side.
    await _ref.read(authRepositoryProvider).logout();
    // 3. Tear down local state.
    await _ref.read(kvCacheProvider).remove(_kCachedUser);
    _invalidateStudentData();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Copy for the confirm dialog shown before [logout].
  ///
  /// The backend has no per-device logout — signing out here ends the session
  /// on every device the student is signed in on. A silent mass logout reads
  /// as a bug, so this must be surfaced before the user commits.
  static const logoutWarning =
      'Signing out will sign you out on all your devices.';

  /// Permanently deletes the signed-in account (Apple 5.1.1(v), Google Play's
  /// account deletion policy).
  ///
  /// On refusal — usually a wrong password — the server's [AppFailure] is
  /// rethrown and nothing local changes: the sheet shows the error and the
  /// student stays signed in, push intact. Teardown starts only once the
  /// server has confirmed.
  ///
  /// That is the reverse of [logout], deliberately. Logout can unregister the
  /// push device first because it has no failure that matters; deletion does,
  /// and unregistering before knowing would leave a student who mistyped their
  /// password signed in but no longer notified. The server deletes device
  /// registrations as part of the deletion instead.
  Future<void> deleteAccount({String? password, String? confirmPhrase}) async {
    await _ref
        .read(authRepositoryProvider)
        .deleteAccount(password: password, confirmPhrase: confirmPhrase);
    await _ref.read(pushServiceProvider).clearLocal();
    await forceLogout(reason: 'account_deleted');
  }

  Future<void> forceLogout({String? reason, String? message}) async {
    await _ref.read(tokenStoreProvider).clear();
    await _ref.read(kvCacheProvider).remove(_kCachedUser);
    _invalidateStudentData();
    AppFailure failure;
    switch (reason) {
      case 'account_blocked':
        failure = AccountBlockedFailure(
          message ?? 'Your account has been blocked. Please contact support.',
        );
        break;
      case 'account_deleted':
        failure = UnauthorizedFailure(
          message ?? 'Your account has been deleted.',
          'account_deleted',
        );
        break;
      case 'session_revoked':
        failure = SessionRevokedFailure(
          message ?? 'You have been signed out. Please sign in again.',
        );
        break;
      default:
        // When secure storage is unavailable the token only ever lived in
        // memory, so the session ends at the next app restart no matter what
        // the server says. "Session expired" is technically true but points
        // the reader at the wrong cause — the build cannot persist a session
        // at all. Say that instead; it is the difference between a five
        // minute diagnosis and an afternoon.
        final ephemeral = _ref.read(tokenStoreProvider).isEphemeral;
        failure = UnauthorizedFailure(
          message ??
              (ephemeral
                  ? 'Signed out because this build cannot store your session '
                      'securely. Sign in again to continue.'
                  : 'Session expired. Please sign in again.'),
        );
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
