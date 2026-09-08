import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network/api_client.dart';
import 'security/capture_event_queue.dart';
import 'security/device_integrity.dart';
import 'security/screen_guard.dart';
import 'storage/kv_cache.dart';
import 'storage/secure_token_store.dart';
import '../features/auth/presentation/auth_controller.dart';

/// Token store singleton.
final tokenStoreProvider =
    Provider<SecureTokenStore>((ref) => SecureTokenStore());

/// Local queue of capture events.
///
/// There is no endpoint to report these to (API_BRIEF has no capture-report
/// route), so they are persisted here rather than dropped. See
/// `lib/core/security/README.md`.
final captureEventQueueProvider = Provider<CaptureEventQueue>(
  (ref) => CaptureEventQueue(ref.read(sharedPreferencesProvider)),
);

/// The single screen-capture protection surface.
///
/// Nothing outside `lib/core/security/` may talk to the platform channel —
/// depend on this instead.
final screenGuardProvider = Provider<ScreenGuard>((ref) {
  final guard = ScreenGuard(queue: ref.read(captureEventQueueProvider));
  ref.onDispose(guard.dispose);
  return guard;
});

/// Root / jailbreak detection. Gates video playback only.
final deviceIntegrityProvider = Provider<DeviceIntegrity>(
  (ref) => DeviceIntegrity(),
);

/// SharedPreferences async provider — overridden in main.dart with a ready instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main.'),
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
