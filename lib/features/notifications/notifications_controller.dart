import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_shared/models.dart';
import '../providers.dart';
import '../sync/app_data_sync.dart';

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<NotificationItem> items;
  final bool loading;
  final Object? error;

  int get unreadCount => items.where((n) => !n.read).length;

  NotificationsState copyWith({
    List<NotificationItem>? items,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) => NotificationsController(ref)..load(),
);

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._ref) : super(const NotificationsState());
  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _ref.read(studentRepositoryProvider).notifications();
      state = NotificationsState(items: items);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> markRead(String id) async {
    final updated = state.items
        .map((n) => n.id == id ? n.copyWith(read: true) : n)
        .toList(growable: false);
    state = state.copyWith(items: updated);
    _ref.read(appDataSyncProvider).onNotificationsReadChanged();
    try {
      await _ref.read(studentRepositoryProvider).markNotificationRead(id);
    } catch (_) {/* swallow — UI already optimistic */}
  }

  Future<void> markAllRead() async {
    final updated =
        state.items.map((n) => n.copyWith(read: true)).toList(growable: false);
    state = state.copyWith(items: updated);
    _ref.read(appDataSyncProvider).onNotificationsReadChanged();
    try {
      await _ref.read(studentRepositoryProvider).markAllNotificationsRead();
    } catch (_) {}
  }

  void prepend(NotificationItem item) {
    state = state.copyWith(items: [item, ...state.items]);
  }
}
