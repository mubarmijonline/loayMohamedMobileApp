import 'package:equatable/equatable.dart';

/// App-wide failure type. UI maps these to user-facing messages.
sealed class AppFailure extends Equatable implements Exception {
  const AppFailure(this.message, {this.code, this.details});
  final String message;
  final String? code;
  final Object? details;

  @override
  List<Object?> get props => [message, code, details];
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'No internet connection.'])
      : super(code: 'network');
}

class TimeoutFailure extends AppFailure {
  const TimeoutFailure([super.message = 'Request timed out.'])
      : super(code: 'timeout');
}

class UnauthorizedFailure extends AppFailure {
  /// [code] carries the server's machine code (API_BRIEF §12) when there is
  /// one — `token_expired`, `invalid_token`, `missing_token`, … — so callers
  /// can branch on it instead of string-matching the message.
  const UnauthorizedFailure([
    super.message = 'Session expired. Please sign in again.',
    String? code,
  ]) : super(code: code ?? 'unauthorized');
}

class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure([
    super.message = 'You do not have access to this resource.',
    String? code,
  ]) : super(code: code ?? 'forbidden');
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'Not found.', String? code])
      : super(code: code ?? 'not_found');
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(
    super.message, {
    super.code = 'validation',
    super.details,
  });
}

class ServerFailure extends AppFailure {
  const ServerFailure([
    super.message = 'Server error. Please try again.',
    String? code,
  ]) : super(code: code ?? 'server');
}

class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Something went wrong.'])
      : super(code: 'unknown');
}

class CacheFailure extends AppFailure {
  const CacheFailure([super.message = 'Local data unavailable.'])
      : super(code: 'cache');
}

class RoleFailure extends AppFailure {
  const RoleFailure([super.message = 'This account is not a student account.'])
      : super(code: 'role');
}

/// Server signalled that this account has been suspended by an admin.
/// HTTP 403 with `error.code == 'account_blocked'`.
class AccountBlockedFailure extends AppFailure {
  const AccountBlockedFailure([
    super.message = 'Your account has been blocked. Please contact support.',
  ]) : super(code: 'account_blocked');
}

/// Server signalled that all sessions for this user were revoked. The mobile
/// token's `tv` claim no longer matches the user's current `token_version`.
/// HTTP 401 with `error.code == 'session_revoked'`.
class SessionRevokedFailure extends AppFailure {
  const SessionRevokedFailure([
    super.message = 'You have been signed out. Please sign in again.',
  ]) : super(code: 'session_revoked');
}

/// A subject was closed by the admin. HTTP 410 with
/// `error.code == 'subject_closed'`.
class SubjectClosedFailure extends AppFailure {
  const SubjectClosedFailure([
    super.message = 'This subject has been closed by the administrator.',
  ]) : super(code: 'subject_closed');
}
