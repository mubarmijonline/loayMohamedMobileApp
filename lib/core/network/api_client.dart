import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../env/app_env.dart';
import '../storage/secure_token_store.dart';
import 'auth_interceptor.dart';
import 'retry_interceptor.dart';

/// Builds a configured Dio client. Used by repositories.
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
      validateStatus: (s) => s != null && s < 500,
    );
    dio = Dio(base);
    final refreshDio = Dio(base.copyWith());

    // Dev/staging: optionally accept self-signed TLS certs (e.g. raw-IP API host).
    // Production keeps default strict validation.
    if (env.allowInsecureTls) {
      IOHttpClientAdapter buildAdapter() => IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.badCertificateCallback =
                  (X509Certificate cert, String host, int port) => true;
              return client;
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
    dio.interceptors.add(RetryInterceptor(dio: dio, maxRetries: env.retryCount));

    if (env.enableLogging) {
      // SECURITY: never log request headers — they carry the
      // `Authorization: Bearer <token>` and other sensitive values.
      dio.interceptors.add(PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: false,
        maxWidth: 120,
      ));
    }
  }

  final SecureTokenStore tokenStore;
  late final Dio dio;
}
