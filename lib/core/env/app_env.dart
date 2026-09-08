import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;

enum Flavor { dev, staging, prod }

/// Build-time overrides, supplied with `--dart-define`.
///
/// The asset `.env` files remain the default so `flutter run` works with no
/// extra flags, but CI and release builds should pass the host explicitly:
///
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://loaymotawie.com
///
/// A `--dart-define` always wins over the bundled asset value.
const String _kApiBaseUrlOverride =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String _kOneSignalAppIdOverride =
    String.fromEnvironment('ONESIGNAL_APP_ID', defaultValue: '');

class AppEnv {
  AppEnv._({
    required this.flavor,
    required this.apiBaseUrl,
    required this.apiV1Prefix,
    required this.legacyStudentPrefix,
    required this.legacyApiPrefix,
    required this.oneSignalAppId,
    required this.connectTimeoutMs,
    required this.receiveTimeoutMs,
    required this.sendTimeoutMs,
    required this.retryCount,
    required this.enableLogging,
    required this.allowInsecureTls,
  });

  final Flavor flavor;
  final String apiBaseUrl;
  final String apiV1Prefix;
  final String legacyStudentPrefix;
  final String legacyApiPrefix;
  final String oneSignalAppId;
  final int connectTimeoutMs;
  final int receiveTimeoutMs;
  final int sendTimeoutMs;
  final int retryCount;
  final bool enableLogging;
  final bool allowInsecureTls;

  static AppEnv? _instance;
  static AppEnv get I {
    final v = _instance;
    if (v == null) {
      throw StateError('AppEnv not initialized. Call AppEnv.load() first.');
    }
    return v;
  }

  static Future<AppEnv> load(Flavor flavor) async {
    final asset = switch (flavor) {
      Flavor.dev => 'assets/env/.env.dev',
      Flavor.staging => 'assets/env/.env.staging',
      Flavor.prod => 'assets/env/.env.prod',
    };
    final raw = await rootBundle.loadString(asset);
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      map[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
    }
    String req(String k) {
      final v = map[k];
      if (v == null || v.isEmpty) {
        throw StateError('Missing env key: $k in $asset');
      }
      return v;
    }

    String pick(String key, String Function() fallback) {
      final override = switch (key) {
        'API_BASE_URL' => _kApiBaseUrlOverride,
        'ONESIGNAL_APP_ID' => _kOneSignalAppIdOverride,
        _ => '',
      };
      return override.isNotEmpty ? override : fallback();
    }

    // Strip a trailing slash so `'$apiBaseUrl$apiV1Prefix'` never doubles up.
    final baseUrl = () {
      final v = pick('API_BASE_URL', () => req('API_BASE_URL'));
      return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
    }();

    _instance = AppEnv._(
      flavor: flavor,
      apiBaseUrl: baseUrl,
      apiV1Prefix: req('API_V1_PREFIX'),
      legacyStudentPrefix: req('LEGACY_STUDENT_PREFIX'),
      legacyApiPrefix: req('LEGACY_API_PREFIX'),
      oneSignalAppId: pick('ONESIGNAL_APP_ID', () => req('ONESIGNAL_APP_ID')),
      connectTimeoutMs: int.parse(req('CONNECT_TIMEOUT_MS')),
      receiveTimeoutMs: int.parse(req('RECEIVE_TIMEOUT_MS')),
      sendTimeoutMs: int.parse(req('SEND_TIMEOUT_MS')),
      retryCount: int.parse(req('RETRY_COUNT')),
      // Never log in release, whatever the .env says. Response bodies carry
      // `embed_url` and the watermark string; neither may reach device logs.
      enableLogging:
          !kReleaseMode && req('ENABLE_LOGGING').toLowerCase() == 'true',
      // TLS validation is never relaxed in a release build.
      allowInsecureTls: !kReleaseMode &&
          (map['ALLOW_INSECURE_TLS']?.toLowerCase() ?? 'false') == 'true',
    );
    return _instance!;
  }

  /// Resolves a (possibly relative) media path returned by the backend to an
  /// absolute URL the client can fetch. Avatars and uploads are served from
  /// the API host root (e.g. `/uploads/avatars/<id>.jpg`) — without this
  /// prefix, `NetworkImage` would fail with an "invalid URL" error.
  ///
  /// Returns the original string for absolute http(s) URLs and `null` for
  /// blank input.
  String? resolveMediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    final suffix = p.startsWith('/') ? p : '/$p';
    return '$base$suffix';
  }
}
