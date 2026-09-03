import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network/api_client.dart';
import 'storage/kv_cache.dart';
import 'storage/secure_token_store.dart';
import '../features/auth/presentation/auth_controller.dart';

/// Token store singleton.
final tokenStoreProvider = Provider<SecureTokenStore>((ref) => SecureTokenStore());

/// SharedPreferences async provider — overridden in main.dart with a ready instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main.'),
);

final kvCacheProvider = Provider<KvCache>(
  (ref) => KvCache(ref.read(sharedPreferencesProvider)),
);

/// Centralized HTTP client. Force-logout hook is wired to AuthController.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStore: ref.read(tokenStoreProvider),
    onForceLogout: ({String? reason, String? message}) async => ref
        .read(authControllerProvider.notifier)
        .forceLogout(reason: reason, message: message),
  );
});
