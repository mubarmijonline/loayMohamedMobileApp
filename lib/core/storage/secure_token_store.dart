import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token bag persisted in secure storage.
class TokenBundle {
  const TokenBundle({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 30)));
  }
}

class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'auth.access_token';
  static const _kRefresh = 'auth.refresh_token';
  static const _kExpires = 'auth.expires_at';

  Future<void> save(TokenBundle b) async {
    await _storage.write(key: _kAccess, value: b.accessToken);
    await _storage.write(key: _kRefresh, value: b.refreshToken);
    await _storage.write(
      key: _kExpires,
      value: b.expiresAt?.toIso8601String(),
    );
  }

  Future<TokenBundle?> read() async {
    final access = await _storage.read(key: _kAccess);
    final refresh = await _storage.read(key: _kRefresh);
    if (access == null || refresh == null) return null;
    final exp = await _storage.read(key: _kExpires);
    return TokenBundle(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: exp == null ? null : DateTime.tryParse(exp),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpires);
  }
}
