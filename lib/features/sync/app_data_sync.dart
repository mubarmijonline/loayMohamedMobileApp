import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../auth/presentation/auth_controller.dart';
import '../notifications/notifications_controller.dart';
import '../parent/student_detail/providers/assignments_provider.dart'
    as parent_assignments;
import '../parent/student_detail/providers/attendance_provider.dart'
    as parent_attendance;
import '../parent/student_detail/providers/notifications_provider.dart'
    as parent_notifications;
import '../parent/student_detail/providers/progress_provider.dart'
    as parent_progress;
import '../parent/student_detail/providers/quizzes_provider.dart'
    as parent_quizzes;
import '../providers.dart';

/// Centralized cache invalidation for cross-feature consistency.
///
/// Any mutation (submit, read, enrollment, etc.) or realtime event (push)
/// should route through this service so all impacted screens refresh together.
class AppDataSync {
  AppDataSync(this._ref);

  final Ref _ref;

  void onRealtimeNotification({Map<String, dynamic>? payload}) {
    AppLogger.I.i('AppDataSync: realtime notification -> refresh all');
    _refreshStudentData();
    _refreshParentData(payload: payload);

    final itemId = _extractItemId(payload);
    if (itemId != null && itemId.isNotEmpty) {
      _ref.invalidate(assignmentProvider(itemId));
    }
  }

  void onAssignmentSubmitted({required String assignmentId}) {
    AppLogger.I.i('AppDataSync: assignment submitted ($assignmentId)');
    _ref.invalidate(assignmentProvider(assignmentId));
    _refreshStudentData();
    _refreshParentData();
  }

  void onNotificationsReadChanged() {
    AppLogger.I.i('AppDataSync: notifications read state changed');
    // Unread counters and dashboard badges depend on read state.
    _ref.invalidate(dashboardProvider);
    // ignore: discarded_futures
    _ref.read(notificationsControllerProvider.notifier).load();
    _refreshParentData();
  }

  void _refreshStudentData() {
    _ref.invalidate(dashboardProvider);
    _ref.invalidate(subjectsProvider);
    _ref.invalidate(enrolledSubjectsProvider);
    _ref.invalidate(enrollmentsProvider);
    _ref.invalidate(assignmentsProvider(null));
    _ref.invalidate(assignmentsProvider('homework'));
    _ref.invalidate(assignmentsProvider('quiz'));
    _ref.invalidate(quizzesProvider);
    _ref.invalidate(subjectWorkloadProvider);
    _ref.invalidate(announcementsProvider('global'));
    _ref.invalidate(contentsProvider);
    // Refresh notifications inbox in-place to preserve any optimistic
    // foreground prepend rather than recreating the controller.
    // ignore: discarded_futures
    _ref.read(notificationsControllerProvider.notifier).load();
  }

  void _refreshParentData({Map<String, dynamic>? payload}) {
    final auth = _ref.read(authControllerProvider);
    final linked = auth.user?.linkedStudents ?? const [];
    if (linked.isEmpty) return;

    final targetStudentId = _extractStudentId(payload);
    for (final s in linked) {
      if (targetStudentId != null &&
          targetStudentId.isNotEmpty &&
          s.id != targetStudentId) {
        continue;
      }
      _ref.invalidate(parent_assignments.assignmentsProvider(s.id));
      _ref.invalidate(parent_quizzes.quizzesProvider(s.id));
      _ref.invalidate(parent_progress.progressProvider(s.id));
      _ref.invalidate(parent_attendance.attendanceProvider(s.id));
      _ref.invalidate(parent_notifications.notificationsProvider(s.id));
    }
  }

  String? _extractStudentId(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    for (final key in const [
      'student_id',
      'studentId',
      'child_id',
      'childId',
      'user_id',
      'userId',
    ]) {
      final value = payload[key]?.toString();
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _extractItemId(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    for (final key in const ['assignment_id', 'quiz_id', 'id', 'item_id']) {
      final value = payload[key]?.toString();
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

final appDataSyncProvider = Provider<AppDataSync>((ref) {
  AppLogger.I.d('AppDataSync provider initialized');
  return AppDataSync(ref);
});
