import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

/// Token bag persisted in secure storage.
///
/// IMPORTANT (API_BRIEF §2): these tokens are **not JWTs**. They are
/// `itsdangerous.URLSafeTimedSerializer` values signed server-side. There is
/// nothing to decode — no `exp` claim, no payload the client may read. Expiry
/// is enforced at verification time from server config, so the only thing the
/// client can do is track the `expires_in` / `refresh_expires_in` values the
/// server returned at login and refresh ahead of them.
///
/// Never add a JWT decoder here.
class TokenBundle {
  const TokenBundle({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
    this.refreshExpiresAt,
    this.issuedAt,
  });

  final String accessToken;
  final String refreshToken;

  /// When the access token stops being accepted.
  final DateTime? expiresAt;

  /// When the refresh token stops being accepted. Past this point the only
  /// path forward is a fresh login.
  final DateTime? refreshExpiresAt;

  /// When this bundle was minted. Used to compute the 80% refresh point.
  final DateTime? issuedAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 30)));
  }

  /// The refresh token itself has expired — refreshing is pointless, the user
  /// must sign in again.
  bool get isRefreshExpired {
    final exp = refreshExpiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  /// API_BRIEF §2.3: "Refresh proactively at ~80% of `expires_in`."
  ///
  /// Computed from the issued/expiry pair rather than a fixed lead time, so a
  /// server that shortens `MOBILE_ACCESS_TOKEN_TTL_SECONDS` is respected
  /// automatically.
  bool get shouldRefreshProactively {
    final exp = expiresAt;
    if (exp == null) return false;
    final start = issuedAt;
    if (start == null) {
      // No issue time recorded (upgraded install) — fall back to a 5 minute
      // lead, still well inside a default 1 hour TTL.
      return DateTime.now().isAfter(exp.subtract(const Duration(minutes: 5)));
    }
    final lifetime = exp.difference(start);
    if (lifetime <= Duration.zero) return true;
    final threshold = start.add(lifetime * 0.8);
    return DateTime.now().isAfter(threshold);
  }

  /// Builds a bundle from an auth payload (`/auth/login`, `/auth/register`,
  /// `/auth/social`, `/auth/refresh` all return the same token fields).
  ///
  /// [fallbackRefresh] is used only when the payload omits `refresh_token`;
  /// every documented response includes one, but a missing value must not
  /// silently wipe the stored token.
  static TokenBundle? fromAuthPayload(
    Map<String, dynamic> data, {
    String? fallbackRefresh,
  }) {
    final access = data['access_token']?.toString();
    if (access == null || access.isEmpty) return null;
    final refresh = data['refresh_token']?.toString() ?? fallbackRefresh;
    if (refresh == null || refresh.isEmpty) return null;
    final now = DateTime.now();
    int? secs(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final expiresIn = secs(data['expires_in']);
    final refreshExpiresIn = secs(data['refresh_expires_in']);
    return TokenBundle(
      accessToken: access,
      refreshToken: refresh,
      issuedAt: now,
      expiresAt:
          expiresIn == null ? null : now.add(Duration(seconds: expiresIn)),
      refreshExpiresAt: refreshExpiresIn == null
          ? null
          : now.add(Duration(seconds: refreshExpiresIn)),
    );
  }
}

class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  /// In-memory fallback, used only when the platform keychain is unavailable.
  ///
  /// This is a *degradation*, not a weakening: memory is never written to
  /// disk, so it is strictly safer than spilling tokens to SharedPreferences.
  /// The cost is that the session does not survive an app restart.
  TokenBundle? _memory;

  /// Debug-only disk cache, used only when the keychain has already refused.
  ///
  /// The iOS Simulator routinely has no usable keychain, so every relaunch of
  /// a dev build landed back on "Session expired" and the developer signed in
  /// again — several times an hour while working on anything behind auth.
  ///
  /// SECURITY: this writes tokens unencrypted, so it is fenced three ways —
  /// `kDebugMode` (never compiled into profile or release), only after the
  /// keychain has actually failed, and cleared by [clear] like any other
  /// store. A release build cannot reach it even if the keychain fails there,
  /// which is the property that matters: on a real device the keychain works,
  /// and if it ever does not, memory-only is the correct degradation.
  final _devCache = kDebugMode ? _DevTokenCache() : null;

  /// Flips false the first time the keychain refuses us. Once false we stop
  /// touching it — otherwise every request retries a call we know will fail,
  /// which is what produced a storm of identical errors and an endless
  /// "Session expired" loop.
  bool _keychainAvailable = true;

  /// True when tokens are being held in memory only, because the platform
  /// keychain is unusable. Surfaced so the UI can say something truthful
  /// instead of blaming an expired session.
  bool get isEphemeral => !_keychainAvailable;

  static const _kAccess = 'auth.access_token';
  static const _kRefresh = 'auth.refresh_token';
  static const _kExpires = 'auth.expires_at';
  static const _kRefreshExpires = 'auth.refresh_expires_at';
  static const _kIssued = 'auth.issued_at';

  /// Records that the keychain is unusable. Logs once, not once per call.
  void _markUnavailable(PlatformException e) {
    if (!_keychainAvailable) return;
    _keychainAvailable = false;
    AppLogger.I.e(
      'Secure storage is unavailable (${e.code}: ${e.message}). Falling back '
      'to in-memory tokens — the session will not survive a restart.\n'
      'On iOS, -34018 (errSecMissingEntitlement) means the build has no '
      'keychain access: either it is unsigned (a simulator build made with '
      'CODE_SIGNING_ALLOWED=NO) or the provisioning profile lacks the '
      'keychain-access-groups entitlement.',
    );
  }

  /// Persists the bundle.
  ///
  /// The in-memory copy is set first and unconditionally, so a keychain
  /// failure costs persistence across restarts but never the current session.
  Future<void> save(TokenBundle b) async {
    _memory = b;
    if (!_keychainAvailable) {
      await _devCache?.write(b);
      return;
    }
    try {
      await _storage.write(key: _kAccess, value: b.accessToken);
      await _storage.write(key: _kRefresh, value: b.refreshToken);
      await _storage.write(
        key: _kExpires,
        value: b.expiresAt?.toIso8601String(),
      );
      await _storage.write(
        key: _kRefreshExpires,
        value: b.refreshExpiresAt?.toIso8601String(),
      );
      await _storage.write(key: _kIssued, value: b.issuedAt?.toIso8601String());
    } on PlatformException catch (e) {
      _markUnavailable(e);
    }
  }

  /// Reads the stored bundle, or null when there is none.
  ///
  /// **Never throws.** This runs on the launch path, and an exception here
  /// escapes `AuthController.bootstrap` and leaves the app on the splash
  /// screen forever. Signed out is recoverable; a frozen splash is not.
  Future<TokenBundle?> read() async {
    if (!_keychainAvailable) return _memory ??= await _devCache?.read();
    try {
      final access = await _storage.read(key: _kAccess);
      final refresh = await _storage.read(key: _kRefresh);
      if (access == null || refresh == null) return null;
      final exp = await _storage.read(key: _kExpires);
      final refreshExp = await _storage.read(key: _kRefreshExpires);
      final issued = await _storage.read(key: _kIssued);
      return TokenBundle(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: exp == null ? null : DateTime.tryParse(exp),
        refreshExpiresAt:
            refreshExp == null ? null : DateTime.tryParse(refreshExp),
        issuedAt: issued == null ? null : DateTime.tryParse(issued),
      );
    } on PlatformException catch (e) {
      _markUnavailable(e);
      return _memory ??= await _devCache?.read();
    }
  }

  /// Clears the stored bundle. Never throws — this runs on the logout and
  /// force-logout paths, where an exception would strand the user half
  /// signed out.
  Future<void> clear() async {
    _memory = null;
    await _devCache?.clear();
    if (!_keychainAvailable) return;
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      await _storage.delete(key: _kExpires);
      await _storage.delete(key: _kRefreshExpires);
      await _storage.delete(key: _kIssued);
    } on PlatformException catch (e) {
      _markUnavailable(e);
    }
  }
}

/// Unencrypted on-disk token cache. **Debug builds only** — see the fence on
/// [SecureTokenStore._devCache]. Exists so a simulator session survives a
/// relaunch; it is never constructed in a release build.
class _DevTokenCache {
  static const _fileName = 'dev_session.json';

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } on Object {
      // Anything here means no dev convenience, which is not worth an error.
      return null;
    }
  }

  Future<void> write(TokenBundle b) async {
    try {
      final f = await _file();
      if (f == null) return;
      await f.writeAsString(
        jsonEncode({
          'access': b.accessToken,
          'refresh': b.refreshToken,
          'expiresAt': b.expiresAt?.toIso8601String(),
          'refreshExpiresAt': b.refreshExpiresAt?.toIso8601String(),
          'issuedAt': b.issuedAt?.toIso8601String(),
        }),
      );
    } on Object {
      // Best effort only.
    }
  }

  Future<TokenBundle?> read() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final access = j['access'] as String?;
      final refresh = j['refresh'] as String?;
      if (access == null || refresh == null) return null;
      DateTime? at(String k) {
        final v = j[k] as String?;
        return v == null ? null : DateTime.tryParse(v);
      }

      return TokenBundle(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: at('expiresAt'),
        refreshExpiresAt: at('refreshExpiresAt'),
        issuedAt: at('issuedAt'),
      );
    } on Object {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (f != null && f.existsSync()) await f.delete();
    } on Object {
      // Best effort only.
    }
  }
}
