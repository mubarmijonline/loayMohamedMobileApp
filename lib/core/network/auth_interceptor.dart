import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_token_store.dart';

/// Adds Authorization Bearer header and triggers refresh on 401.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.tokenStore,
    required this.refreshClient,
    required this.refreshPath,
    required this.onForceLogout,
  });

  final SecureTokenStore tokenStore;
  final Dio refreshClient;
  final String refreshPath;
  final Future<void> Function({String? reason, String? message}) onForceLogout;

  bool _refreshing = false;

  /// Reads the server-supplied error code from a Dio response, if any.
  /// Backend envelope shape is `{ "error": { "code": "...", "message": "..." } }`.
  static Map<String, String?> _readError(Response<dynamic>? res) {
    final data = res?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        return {
          'code': err['code']?.toString(),
          'message': err['message']?.toString(),
        };
      }
    }
    return const {'code': null, 'message': null};
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }
    final tokens = await tokenStore.read();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final status = res?.statusCode;
    final errInfo = _readError(res);
    final code = errInfo['code'];

    // Server explicitly signalled the account is blocked or the session was
    // revoked. Do NOT attempt token refresh — drop tokens immediately and
    // route the user back to login with a reason.
    if (code == 'account_blocked' || code == 'session_revoked') {
      await onForceLogout(reason: code, message: errInfo['message']);
      return handler.next(err);
    }

    if (status != 401 || err.requestOptions.extra['skipAuth'] == true) {
      return handler.next(err);
    }
    if (err.requestOptions.extra['retried'] == true) {
      await onForceLogout();
      return handler.next(err);
    }
    final tokens = await tokenStore.read();
    if (tokens == null) {
      await onForceLogout();
      return handler.next(err);
    }
    try {
      if (!_refreshing) {
        _refreshing = true;
        try {
          final response = await refreshClient.post<Map<String, dynamic>>(
            refreshPath,
            data: {'refresh_token': tokens.refreshToken},
            options: Options(extra: const {'skipAuth': true}),
          );
          final body = response.data;
          // Refresh itself may report account_blocked / session_revoked.
          final refreshErr = _readError(response);
          final refreshCode = refreshErr['code'];
          if (refreshCode == 'account_blocked' ||
              refreshCode == 'session_revoked') {
            await onForceLogout(
              reason: refreshCode,
              message: refreshErr['message'],
            );
            return handler.next(err);
          }
          final data = (body?['data'] ?? body) as Map<String, dynamic>?;
          if (data == null) {
            throw DioException(requestOptions: err.requestOptions, response: response);
          }
          final access = data['access_token']?.toString();
          final refresh = (data['refresh_token'] ?? tokens.refreshToken).toString();
          final expiresIn = data['expires_in'];
          if (access == null) {
            throw DioException(requestOptions: err.requestOptions, response: response);
          }
          await tokenStore.save(
            TokenBundle(
              accessToken: access,
              refreshToken: refresh,
              expiresAt: expiresIn is int
                  ? DateTime.now().add(Duration(seconds: expiresIn))
                  : null,
            ),
          );
        } finally {
          _refreshing = false;
        }
      }
      // Retry the original request with the new token.
      final newTokens = await tokenStore.read();
      final req = err.requestOptions;
      req.headers['Authorization'] = 'Bearer ${newTokens?.accessToken}';
      req.extra['retried'] = true;
      final dio = Dio(BaseOptions(
        baseUrl: req.baseUrl,
        connectTimeout: req.connectTimeout,
        receiveTimeout: req.receiveTimeout,
        sendTimeout: req.sendTimeout,
      ));
      final cloned = await dio.fetch<dynamic>(req);
      return handler.resolve(cloned);
    } catch (_) {
      await onForceLogout();
      return handler.next(err);
    }
  }
}
