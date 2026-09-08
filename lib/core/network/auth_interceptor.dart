import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_token_store.dart';

/// Attaches the bearer token, refreshes proactively at 80% of the access
/// token's life, and recovers from a 401 with a **single-flight** refresh.
///
/// API_BRIEF §2:
///  * Tokens are `itsdangerous` values, not JWTs — nothing here decodes them.
///  * `/auth/refresh` rotates **both** tokens. Both must be persisted or the
///    next refresh fails with `invalid_refresh_token`.
///  * Concurrent 401s must queue behind one refresh call and then replay.
///    Parallel refreshes rotate each other out and log the user out.
///  * `session_revoked` / `account_blocked` are terminal — never retried.
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

  /// The in-flight refresh, if any. Every caller awaits this same future, so
  /// only one `/auth/refresh` request is ever on the wire at a time.
  Future<TokenBundle?>? _inFlight;

  /// Server codes that mean "this session is over" — refreshing cannot help.
  ///
  /// API_BRIEF §13.3 notes `/auth/refresh` does not check `token_version`, so
  /// a refresh **succeeds** after logout and mints an access token that is
  /// then rejected on use. Treat `session_revoked` as terminal regardless of
  /// whether a refresh appeared to work.
  static const _terminalCodes = {
    'session_revoked',
    'account_blocked',
    'user_not_found',
    'inactive_account',
    'forbidden_role',
  };

  /// Refresh-endpoint codes that mean the refresh token is spent.
  static const _refreshDeadCodes = {
    'refresh_expired',
    'invalid_refresh_token',
    'invalid_payload',
    'missing_refresh_token',
  };

  /// Reads the server error code/message out of a response body.
  /// Envelope shape is `{ "error": { "code": "...", "message": "..." } }`.
  static ({String? code, String? message}) _readError(Response<dynamic>? res) {
    final data = res?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        return (
          code: err['code']?.toString(),
          message: err['message']?.toString(),
        );
      }
    }
    return (code: null, message: null);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }
    var tokens = await tokenStore.read();

    // Proactive refresh: past 80% of the access token's life, renew before
    // spending a round trip on a 401 we can already predict.
    if (tokens != null &&
        tokens.shouldRefreshProactively &&
        !tokens.isRefreshExpired) {
      tokens = await _refreshOnce(tokens) ?? tokens;
    }

    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final res = err.response;
    final status = res?.statusCode;
    final info = _readError(res);

    // Terminal — drop tokens and route to login without retrying.
    if (info.code != null && _terminalCodes.contains(info.code)) {
      await onForceLogout(reason: info.code, message: info.message);
      return handler.next(err);
    }

    if (status != 401 || err.requestOptions.extra['skipAuth'] == true) {
      return handler.next(err);
    }
    // Already replayed once with a fresh token and still 401 — give up.
    if (err.requestOptions.extra['retried'] == true) {
      await onForceLogout(reason: info.code, message: info.message);
      return handler.next(err);
    }

    final tokens = await tokenStore.read();
    if (tokens == null || tokens.isRefreshExpired) {
      await onForceLogout(reason: info.code ?? 'token_expired');
      return handler.next(err);
    }

    final refreshed = await _refreshOnce(tokens);
    if (refreshed == null) {
      // _refreshOnce already forced logout with the right reason.
      return handler.next(err);
    }

    try {
      final req = err.requestOptions;
      req.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
      req.extra['retried'] = true;
      // Replay on the refresh client: it shares the base options but carries
      // no interceptors, so this cannot recurse back into onError.
      final cloned = await refreshClient.fetch<dynamic>(req);
      return handler.resolve(cloned);
    } on DioException catch (e) {
      final replayInfo = _readError(e.response);
      if (e.response?.statusCode == 401) {
        await onForceLogout(
          reason: replayInfo.code ?? 'token_expired',
          message: replayInfo.message,
        );
      }
      return handler.next(e);
    } catch (_) {
      return handler.next(err);
    }
  }

  /// Runs at most one refresh at a time. Concurrent callers await the same
  /// future and all receive the same rotated bundle.
  ///
  /// Returns `null` when the session is over; in that case logout has already
  /// been triggered with the appropriate reason.
  Future<TokenBundle?> _refreshOnce(TokenBundle current) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _doRefresh(current).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<TokenBundle?> _doRefresh(TokenBundle current) async {
    try {
      final response = await refreshClient.post<dynamic>(
        refreshPath,
        data: {'refresh_token': current.refreshToken},
        options: Options(extra: const {'skipAuth': true}),
      );
      final body = response.data;
      final info = _readError(response);

      // The refresh route can itself report a dead session.
      if (info.code != null &&
          (_terminalCodes.contains(info.code) ||
              _refreshDeadCodes.contains(info.code))) {
        await onForceLogout(reason: info.code, message: info.message);
        return null;
      }

      final map = body is Map ? Map<String, dynamic>.from(body) : null;
      if (map == null || map['success'] == false) {
        await onForceLogout(reason: info.code ?? 'invalid_refresh_token');
        return null;
      }
      final data = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;

      // Both tokens rotate. Persist both — keeping the old refresh token
      // breaks the next refresh.
      final bundle = TokenBundle.fromAuthPayload(
        data,
        fallbackRefresh: current.refreshToken,
      );
      if (bundle == null) {
        await onForceLogout(reason: 'invalid_refresh_token');
        return null;
      }
      await tokenStore.save(bundle);
      return bundle;
    } on DioException catch (e) {
      final info = _readError(e.response);
      await onForceLogout(
        reason: info.code ?? 'refresh_failed',
        message: info.message,
      );
      return null;
    } catch (_) {
      await onForceLogout(reason: 'refresh_failed');
      return null;
    }
  }
}
