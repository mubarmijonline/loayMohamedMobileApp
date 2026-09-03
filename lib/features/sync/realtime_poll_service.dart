import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../auth/presentation/auth_controller.dart';
import '../notifications/notifications_controller.dart';
import '../providers.dart';
import 'app_data_sync.dart';

/// Periodically polls the server for the latest notifications and, when a new
/// one is detected, refreshes the inbox + triggers global [AppDataSync].
///
/// Used as a fallback when remote push isn't available (e.g. iOS simulator,
/// permission denied, or transient delivery failure). Also re-polls
/// immediately when the app comes back to the foreground.
class RealtimePollService with WidgetsBindingObserver {
  RealtimePollService(this._ref);
  final Ref _ref;

  Timer? _timer;
  String? _lastId;
  bool _running = false;
  bool _ticking = false;

  static const _interval = Duration(seconds: 15);

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => _tick());
    // Seed _lastId from the current snapshot without firing a refresh.
    _tick(seed: true);
    AppLogger.I.i('RealtimePoll: started (interval=${_interval.inSeconds}s)');
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _lastId = null;
    WidgetsBinding.instance.removeObserver(this);
    AppLogger.I.i('RealtimePoll: stopped');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      AppLogger.I.d('RealtimePoll: app resumed -> immediate tick');
      _tick();
    }
  }

  Future<void> _tick({bool seed = false}) async {
    if (_ticking) return;
    _ticking = true;
    try {
      final repo = _ref.read(studentRepositoryProvider);
      final items = await repo.notificationsLatest().catchError(
            (_) => repo.notifications(),
          );
      if (items.isEmpty) return;
      final newestId = items.first.id;
      if (seed || _lastId == null) {
        _lastId = newestId;
        return;
      }
      if (newestId == _lastId) return;

      AppLogger.I.i('RealtimePoll: new notification detected ($newestId)');
      _lastId = newestId;

      // Refresh inbox immediately so the badge + list update.
      await _ref.read(notificationsControllerProvider.notifier).load();

      // Fan out to every dependent provider (student + parent caches).
      _ref
          .read(appDataSyncProvider)
          .onRealtimeNotification(payload: items.first.data);
    } catch (e) {
      AppLogger.I.w('RealtimePoll: tick failed: $e');
    } finally {
      _ticking = false;
    }
  }
}

final realtimePollServiceProvider =
    Provider<RealtimePollService>((ref) => RealtimePollService(ref));

/// Side-effect: start/stop polling based on auth state. Mirrors
/// [pushBootstrapProvider]'s lifecycle.
final realtimePollBootstrapProvider = Provider<void>((ref) {
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    final svc = ref.read(realtimePollServiceProvider);
    if (next.status == AuthStatus.authenticated) {
      svc.start();
    } else {
      svc.stop();
    }
  }, fireImmediately: true);
});
