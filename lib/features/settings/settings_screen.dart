import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/providers.dart';
import '../../core/storage/kv_cache.dart';
import '../auth/presentation/auth_controller.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) {
    final controller = ThemeModeController(ref.read(kvCacheProvider));
    // Reload the saved theme whenever the signed-in user changes so each
    // student gets their own preference.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.user?.id != next.user?.id) {
        controller.reloadForUser(next.user?.id);
      }
    }, fireImmediately: true);
    return controller;
  },
);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._cache) : super(_load(_cache, null));
  final KvCache _cache;
  String? _userId;

  static String _key(String? userId) => userId == null || userId.isEmpty
      ? 'settings.theme'
      : 'settings.theme.$userId';

  /// The key the web student portal uses (`docs/mobile/THEME_SPEC.md` §6).
  ///
  /// Kept in sync alongside the per-user keys so support can reason about both
  /// clients at once. The per-user key still wins when present — two students
  /// sharing a phone should not share a theme, which the portal's single key
  /// cannot express.
  static const portalKey = 'loay-student-color-mode';

  static ThemeMode _load(KvCache c, String? userId) {
    switch (c.getString(_key(userId))) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        // Fall back to the legacy global key for backwards compatibility.
        if (userId != null) {
          switch (c.getString('settings.theme')) {
            case 'light':
              return ThemeMode.light;
            case 'dark':
              return ThemeMode.dark;
          }
        }
        // Then the portal's own key, so a student who set dark mode on the web
        // finds the app already in dark mode.
        switch (c.getString(portalKey)) {
          case 'light':
            return ThemeMode.light;
          case 'dark':
            return ThemeMode.dark;
        }
        return ThemeMode.system;
    }
  }

  void reloadForUser(String? userId) {
    _userId = userId;
    state = _load(_cache, userId);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final value = mode == ThemeMode.light
        ? 'light'
        : (mode == ThemeMode.dark ? 'dark' : 'system');
    await _cache.setString(_key(_userId), value);
    // Mirror to the portal's key so the two clients read the same value.
    // `system` is not one of the portal's values, so it is cleared rather than
    // written — a stray 'system' there would confuse the web client.
    if (mode == ThemeMode.system) {
      await _cache.remove(portalKey);
    } else {
      await _cache.setString(portalKey, value);
    }
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final cache = ref.read(kvCacheProvider);
    final pushEnabled = OneSignal.User.pushSubscription.optedIn ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          PremiumCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Push notifications'),
                  subtitle: const Text(
                      'Receive announcements, due dates, and grades.'),
                  value: pushEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await OneSignal.Notifications.requestPermission(true);
                      OneSignal.User.pushSubscription.optIn();
                    } else {
                      OneSignal.User.pushSubscription.optOut();
                    }
                    await cache.setBool('settings.push', v);
                    (context as Element).markNeedsBuild();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PremiumCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System theme'),
                  value: ThemeMode.system,
                  groupValue: mode,
                  onChanged: (v) =>
                      ref.read(themeModeProvider.notifier).set(v!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: mode,
                  onChanged: (v) =>
                      ref.read(themeModeProvider.notifier).set(v!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: mode,
                  onChanged: (v) =>
                      ref.read(themeModeProvider.notifier).set(v!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
