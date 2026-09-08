import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../env/app_env.dart';
import '../logging/app_logger.dart';
import '../security/certificate_pinning.dart';
import '../storage/secure_token_store.dart';
import 'auth_interceptor.dart';
import 'retry_interceptor.dart';

/// Builds the single configured Dio client used by every repository.
class ApiClient {
  ApiClient({
    required this.tokenStore,
    required Future<void> Function({String? reason, String? message})
        onForceLogout,
  }) {
    final env = AppEnv.I;
    final base = BaseOptions(
      baseUrl: env.apiBaseUrl,
      connectTimeout: Duration(milliseconds: env.connectTimeoutMs),
      receiveTimeout: Duration(milliseconds: env.receiveTimeoutMs),
      sendTimeout: Duration(milliseconds: env.sendTimeoutMs),
      contentType: 'application/json',
      responseType: ResponseType.json,
      headers: const {
        'Accept': 'application/json',
        'X-Client': 'mobile',
      },
      // Only 2xx is a success. Everything else must surface as a
      // DioException so AuthInterceptor.onError can run the refresh flow and
      // ErrorMapper can read `error.code` off the envelope.
      //
      // Do NOT widen this to `s < 500`: that swallows every 401 into a normal
      // response, the 401 handler never fires, and the app sits on a dead
      // access token showing "Request failed" until the user force-quits.
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    );
    dio = Dio(base);

    // Interceptor-free client. Used for /auth/refresh and for replaying a
    // request after a refresh, so neither can recurse back into onError.
    final refreshDio = Dio(base.copyWith());

    // TLS policy.
    //
    // Two independent things happen here:
    //  * `allowInsecureTls` (dev/staging only — AppEnv forces it false in
    //    release) accepts self-signed certs for a local backend.
    //  * Certificate pinning constrains the API host to a known SPKI. Pinning
    //    only ever *adds* a constraint; with no pins configured it is inert
    //    and normal system validation applies.
    //
    // Pinning is enforced on the connection callback, not only on
    // `badCertificateCallback`: the latter fires only when system validation
    // already failed, so a proxy CA the device trusts would sail past it —
    // which is exactly the MITM case pinning exists to stop.
    final pinning = CertificatePinning(host: Uri.parse(env.apiBaseUrl).host);
    if (pinning.isEnabled) {
      AppLogger.I.i('TLS pinning active (${pinning.pins.length} pins)');
    } else if (kReleaseMode) {
      AppLogger.I.w(
        'TLS pinning is NOT configured — pass --dart-define=SPKI_PINS to '
        'enable it. See lib/core/security/certificate_pinning.dart.',
      );
    }

    if (env.allowInsecureTls || pinning.isEnabled) {
      IOHttpClientAdapter buildAdapter() => IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              if (env.allowInsecureTls) {
                client.badCertificateCallback =
                    (X509Certificate cert, String host, int port) => true;
              } else if (pinning.isEnabled) {
                client.badCertificateCallback = pinning.allowCertificate;
              }
              return client;
            },
            validateCertificate: (cert, host, port) {
              // Not our host (CDN, avatar, Bunny) — system validation stands.
              if (host != pinning.host) return true;
              if (cert == null) return false;
              return pinning.isPinned(cert);
            },
          );
      dio.httpClientAdapter = buildAdapter();
      refreshDio.httpClientAdapter = buildAdapter();
    }

    dio.interceptors.add(
      AuthInterceptor(
        tokenStore: tokenStore,
        refreshClient: refreshDio,
        refreshPath: '${env.apiV1Prefix}/auth/refresh',
        onForceLogout: onForceLogout,
      ),
    );
    dio.interceptors
        .add(RetryInterceptor(dio: dio, maxRetries: env.retryCount));

    if (env.enableLogging) {
      // SECURITY: never log request headers — they carry the
      // `Authorization: Bearer <token>`. Response bodies are logged in dev
      // only; `embed_url` and the watermark string must not reach a release
      // build's logs (AppEnv forces enableLogging=false in release).
      //
      // `requestBody` is off because PrettyDioLogger prints `options.data`
      // verbatim, and the login and register payloads carry the user's
      // password in plain text. Confirmed on 2026-09-08: a dev run wrote the
      // real password of a live account into the device log, where it stays
      // readable to anyone with the handset or the console. The redacting
      // logger below prints the same bodies with the secret fields masked.
      dio.interceptors
        ..add(const _RedactedRequestLogger())
        ..add(
          PrettyDioLogger(
            requestHeader: false,
            requestBody: false,
            responseBody: true,
            responseHeader: false,
            error: true,
            compact: false,
            maxWidth: 120,
          ),
        );
    }
  }

  final SecureTokenStore tokenStore;
  late final Dio dio;
}

/// Logs request bodies with credential fields masked.
///
/// Dev builds only — it is installed alongside the pretty logger, which has
/// its own `requestBody` disabled precisely so this one owns the job.
class _RedactedRequestLogger extends Interceptor {
  const _RedactedRequestLogger();

  /// Masked wherever they appear, at any depth.
  ///
  /// Matching is on the whole key, lower-cased. A substring match would be
  /// tempting but would also mask `password_updated_at`-style metadata that is
  /// useful in a log and is not itself a secret.
  static const _secretKeys = <String>{
    'password',
    'current_password',
    'new_password',
    'confirm_password',
    'password_confirmation',
    'old_password',
    'pin',
    'otp',
    'code',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'secret',
    'client_secret',
  };

  static Object? redact(Object? value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: _secretKeys.contains(e.key.toString().toLowerCase())
              ? '<redacted>'
              : redact(e.value),
      };
    }
    if (value is List) return value.map(redact).toList();
    return value;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    if (data != null && data is! FormData) {
      AppLogger.I.d('→ ${options.method} ${options.path} ${redact(data)}');
    } else if (data is FormData) {
      // A multipart upload is a file, not a credential payload; log its shape
      // rather than its bytes.
      AppLogger.I.d(
        '→ ${options.method} ${options.path} '
        '(multipart: ${data.fields.length} fields, ${data.files.length} files)',
      );
    }
    handler.next(options);
  }
}

/// Test-only handle on the masking above.
///
/// The interceptor itself is private because nothing should install it by
/// hand, but the redaction rule is the part worth pinning, so it is reachable.
@visibleForTesting
Object? debugRedactForTest(Object? value) =>
    _RedactedRequestLogger.redact(value);
