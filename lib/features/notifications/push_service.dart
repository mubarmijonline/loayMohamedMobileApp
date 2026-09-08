import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/env/app_env.dart';
import '../../core/logging/app_logger.dart';
import '../../core/providers.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../notifications/notifications_controller.dart';
import '../providers.dart';
import '../sync/app_data_sync.dart';

/// Encapsulates OneSignal lifecycle: init, permission, identity, payload routing.
class PushService {
  PushService(this._ref);
  final Ref _ref;

  static const _kPlayerIdKey = 'push.player_id';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    OneSignal.Debug.setLogLevel(
      AppEnv.I.enableLogging ? OSLogLevel.warn : OSLogLevel.none,
    );
    OneSignal.initialize(AppEnv.I.oneSignalAppId);

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Show the OS banner; also push to local inbox for in-session UX.
      _onForeground(event.notification);
      event.notification.display();
    });

    OneSignal.Notifications.addClickListener((event) {
      _onTap(event.notification);
    });
  }

  /// Soft pre-prompt + native permission request.
  Future<bool> requestPermission(BuildContext context) async {
    final cache = _ref.read(kvCacheProvider);
    if (cache.getBool('push.prompted', defaultValue: false)) {
      return OneSignal.Notifications.permission;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stay in the loop'),
        content: const Text(
          'Get notified about new lessons, assignments, grades, and announcements from your teacher.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    await cache.setBool('push.prompted', true);
    if (accepted != true) return false;
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Bind OneSignal external user id to [userId] and register device on backend.
  /// [role] is forwarded as an OneSignal tag and as a field in the device
  /// registration payload so the backend can target parent vs student devices.
  Future<void> bindUser(String userId, String role) async {
    try {
      AppLogger.I.i('OneSignal.bindUser: login($userId) role=$role');
      OneSignal.login(userId);
      // Tag the device role so push campaigns can target role segments.
      OneSignal.User.addTagWithKey('role', role);
      // Wait for player id to be assigned. OneSignal v5 exposes pushSubscription.id.
      String? playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) {
        for (var i = 0; i < 5 && (playerId == null || playerId.isEmpty); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          playerId = OneSignal.User.pushSubscription.id;
        }
      }
      if (playerId == null || playerId.isEmpty) {
        AppLogger.I.w(
          'OneSignal: no player_id after wait — likely simulator or '
          'permission not granted. Skipping backend register.',
        );
        return;
      }
      AppLogger.I.i(
        'OneSignal player_id=$playerId — registering with backend (role=$role)',
      );
      final cache = _ref.read(kvCacheProvider);
      await cache.setString(_kPlayerIdKey, playerId);

      final pkg = await PackageInfo.fromPlatform();
      final di = DeviceInfoPlugin();
      String? model;
      String? osVer;
      if (Platform.isAndroid) {
        final a = await di.androidInfo;
        model = a.model;
        osVer = 'Android ${a.version.release}';
      } else if (Platform.isIOS) {
        final i = await di.iosInfo;
        model = i.utsname.machine;
        osVer = 'iOS ${i.systemVersion}';
      }
      await _ref.read(studentRepositoryProvider).registerPushDevice(
            oneSignalPlayerId: playerId,
            platform: Platform.isIOS ? 'ios' : 'android',
            appVersion: '${pkg.version}+${pkg.buildNumber}',
            deviceModel: model,
            osVersion: osVer,
            role: role,
          );
      AppLogger.I.i('OneSignal device registered with backend ✓ (role=$role)');
    } catch (e, st) {
      AppLogger.I.w('OneSignal bind failed: $e\n$st');
    }
  }

  Future<void> unbind() async {
    try {
      final cache = _ref.read(kvCacheProvider);
      final playerId = cache.getString(_kPlayerIdKey);
      if (playerId != null) {
        await _ref
            .read(studentRepositoryProvider)
            .unregisterPushDevice(playerId);
      }
      await cache.remove(_kPlayerIdKey);
      OneSignal.logout();
    } catch (e) {
      AppLogger.I.w('OneSignal unbind failed: $e');
    }
  }

  void _onForeground(OSNotification n) {
    final data = n.additionalData == null
        ? null
        : Map<String, dynamic>.from(n.additionalData!);
    final item = NotificationItem(
      id: n.notificationId,
      title: n.title ?? '',
      body: n.body ?? '',
      createdAt: DateTime.now(),
      read: false,
      category: n.additionalData?['category']?.toString(),
      deepLink: n.additionalData?['deep_link']?.toString() ?? n.launchUrl,
      data: data,
    );
    _ref.read(notificationsControllerProvider.notifier).prepend(item);
    _ref.read(appDataSyncProvider).onRealtimeNotification(payload: data);
  }

  void _onTap(OSNotification n) {
    final data = n.additionalData == null
        ? null
        : Map<String, dynamic>.from(n.additionalData!);
    _ref.read(appDataSyncProvider).onRealtimeNotification(payload: data);
    final route = _routeFor(n);
    if (route == null) return;
    final navigator = _ref.read(rootNavigatorKeyProvider).currentState;
    navigator?.pushNamed(route);
  }

  String? _routeFor(OSNotification n) {
    final deepLink = n.additionalData?['deep_link']?.toString();
    if (deepLink != null && deepLink.startsWith('/')) return deepLink;
    final category = n.additionalData?['category']?.toString();
    final kind = n.additionalData?['kind']?.toString();
    final id = n.additionalData?['id']?.toString();
    // Cloudflare Stream video deep link:
    //   data: { kind: 'video', class_id: '...', group_title: '...' }
    if (kind == 'video' || category == 'video') {
      final classId = n.additionalData?['class_id']?.toString();
      final group = n.additionalData?['group_title']?.toString();
      if (classId != null && classId.isNotEmpty) {
        if (group != null && group.isNotEmpty) {
          return '/classes/$classId/videos?group=${Uri.encodeComponent(group)}';
        }
        return '/classes/$classId/videos';
      }
    }
    switch (category) {
      case 'announcement':
        return '/announcements';
      case 'assignment_due':
        return id == null ? '/assignments' : '/assignments/$id';
      case 'quiz_due':
        return id == null ? '/quizzes' : '/assignments/$id';
      case 'grade_posted':
        return id == null ? '/assignments' : '/assignments/$id';
      case 'enrollment_update':
        return '/subjects';
      default:
        return '/notifications';
    }
  }
}

/// Global navigator key, used by push routing.
final rootNavigatorKeyProvider =
    Provider<GlobalKey<NavigatorState>>((ref) => GlobalKey<NavigatorState>());

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

/// Side-effect: when the user becomes authenticated, init/bind OneSignal;
/// when unauthenticated, tear down the local OneSignal session.
///
/// NOTE: the `DELETE /devices/<player_id>` call is NOT made here. This
/// listener fires *after* tokens are already cleared, so the request would
/// 401 and the device would stay registered. `AuthController.logout()` calls
/// [PushService.unbind] first, while the token is still valid — see
/// API_BRIEF §4. This branch is only the safety net for a forced logout
/// (session revoked / account blocked), where the token is dead anyway.
final pushBootstrapProvider = Provider<void>((ref) {
  ref.listen<AuthState>(authControllerProvider, (prev, next) async {
    final svc = ref.read(pushServiceProvider);
    if (next.status == AuthStatus.authenticated && next.user != null) {
      await svc.init();
      await svc.bindUser(next.user!.id, next.user!.role);
    } else if (next.status == AuthStatus.unauthenticated) {
      // No-op when logout() already unbound; clears local state otherwise.
      await svc.unbind();
    }
  });
});
