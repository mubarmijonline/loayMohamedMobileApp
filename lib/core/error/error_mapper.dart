import 'package:dio/dio.dart';

import 'failures.dart';

class ErrorMapper {
  ErrorMapper._();

  static AppFailure fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        final msg = e.error?.toString() ?? e.message ?? 'Connection failed.';
        return NetworkFailure('Cannot reach server: $msg');
      case DioExceptionType.cancel:
        return const UnknownFailure('Request was cancelled.');
      case DioExceptionType.badCertificate:
        return const ServerFailure('Server certificate is not trusted.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return _fromResponse(e);
    }
  }

  static AppFailure _fromResponse(DioException e) {
    final res = e.response;
    final status = res?.statusCode ?? 0;
    final data = res?.data;
    String? message;
    String? code;
    Object? details;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        code = err['code']?.toString();
        message = err['message']?.toString();
        details = err['details'];
      } else {
        message = data['message']?.toString();
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    }
    message ??= 'Request failed (status $status).';

    // Server-driven codes that map to dedicated failure types regardless of
    // the HTTP status (the brief allows e.g. account_blocked under 403 and
    // session_revoked under 401, but we also tolerate alternate statuses).
    switch (code) {
      case 'account_blocked':
        return AccountBlockedFailure(message);
      case 'session_revoked':
        return SessionRevokedFailure(message);
      case 'subject_closed':
        return SubjectClosedFailure(message);
    }

    if (status == 410) {
      return SubjectClosedFailure(message);
    }
    if (status == 401) return UnauthorizedFailure(message);
    if (status == 403) return ForbiddenFailure(message);
    if (status == 404) return NotFoundFailure(message);
    if (status == 422 || status == 400) {
      return ValidationFailure(message, code: code, details: details);
    }
    if (status >= 500) return ServerFailure(message);
    return UnknownFailure(message);
  }

  static AppFailure fromObject(Object e, [StackTrace? st]) {
    if (e is AppFailure) return e;
    if (e is DioException) return fromDio(e);
    return UnknownFailure(e.toString());
  }
}
