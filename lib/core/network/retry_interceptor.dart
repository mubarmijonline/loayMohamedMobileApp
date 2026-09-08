import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Retries idempotent requests on transient network/server errors.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({required this.dio, this.maxRetries = 2});

  final Dio dio;
  final int maxRetries;

  static const _retriableMethods = {'GET', 'HEAD'};

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final attempt = (req.extra['retry_attempt'] as int?) ?? 0;
    final method = req.method.toUpperCase();
    final retriable = _retriableMethods.contains(method) && _isTransient(err);

    if (!retriable || attempt >= maxRetries) {
      return handler.next(err);
    }
    final delay = Duration(milliseconds: 300 * (attempt + 1));
    await Future<void>.delayed(delay);
    req.extra['retry_attempt'] = attempt + 1;
    try {
      final response = await dio.fetch<dynamic>(req);
      return handler.resolve(response);
    } catch (e) {
      if (e is DioException) return handler.next(e);
      return handler.next(err);
    }
  }

  bool _isTransient(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return true;
    }
    if (e.error is SocketException) return true;
    final status = e.response?.statusCode ?? 0;
    return status >= 500 && status <= 599;
  }
}
