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
  const NetworkFailure([String message = 'No internet connection.']) : super(message, code: 'network');
}

class TimeoutFailure extends AppFailure {
  const TimeoutFailure([String message = 'Request timed out.']) : super(message, code: 'timeout');
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([String message = 'Session expired. Please sign in again.'])
      : super(message, code: 'unauthorized');
}

class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure([String message = 'You do not have access to this resource.'])
      : super(message, code: 'forbidden');
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([String message = 'Not found.']) : super(message, code: 'not_found');
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.code = 'validation', super.details});
}

class ServerFailure extends AppFailure {
  const ServerFailure([String message = 'Server error. Please try again.']) : super(message, code: 'server');
}

class UnknownFailure extends AppFailure {
  const UnknownFailure([String message = 'Something went wrong.']) : super(message, code: 'unknown');
}

class CacheFailure extends AppFailure {
  const CacheFailure([String message = 'Local data unavailable.']) : super(message, code: 'cache');
}

class RoleFailure extends AppFailure {
  const RoleFailure([String message = 'This account is not a student account.']) : super(message, code: 'role');
}

/// Server signalled that this account has been suspended by an admin.
/// HTTP 403 with `error.code == 'account_blocked'`.
class AccountBlockedFailure extends AppFailure {
  const AccountBlockedFailure(
      [String message =
          'Your account has been blocked. Please contact support.'])
      : super(message, code: 'account_blocked');
}

/// Server signalled that all sessions for this user were revoked. The mobile
/// token's `tv` claim no longer matches the user's current `token_version`.
/// HTTP 401 with `error.code == 'session_revoked'`.
class SessionRevokedFailure extends AppFailure {
  const SessionRevokedFailure(
      [String message = 'You have been signed out. Please sign in again.'])
      : super(message, code: 'session_revoked');
}

/// A subject was closed by the admin. HTTP 410 with
/// `error.code == 'subject_closed'`.
class SubjectClosedFailure extends AppFailure {
  const SubjectClosedFailure(
      [String message =
          'This subject has been closed by the administrator.'])
      : super(message, code: 'subject_closed');
}
