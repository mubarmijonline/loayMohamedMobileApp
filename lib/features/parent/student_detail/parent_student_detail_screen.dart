import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import '../../auth/domain/student_user.dart';
import 'providers/assignments_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/quizzes_provider.dart';
import 'widgets/activity_notification_card.dart';
import 'widgets/assignment_card.dart';
import 'widgets/attendance_record_tile.dart';
import 'widgets/attendance_summary_row.dart';
import 'widgets/progress_summary.dart';
import 'widgets/quiz_card.dart';
import 'widgets/section_empty.dart';
import 'widgets/section_error.dart';
import 'widgets/section_loading.dart';

/// Parent → linked-student detail screen. Each of the 5 sections lazy-loads
/// its data only when the parent expands the section.
class ParentStudentDetailScreen extends ConsumerStatefulWidget {
  const ParentStudentDetailScreen({super.key, required this.student});
  final LinkedStudent student;

  @override
  ConsumerState<ParentStudentDetailScreen> createState() =>
      _ParentStudentDetailScreenState();
}

class _ParentStudentDetailScreenState
    extends ConsumerState<ParentStudentDetailScreen> {
  // Track which sections have ever been opened so that pull-to-refresh
  // invalidates only the ones the user actually loaded.
  final Set<int> _loaded = <int>{};

  String get _id => widget.student.id;

  Future<void> _refresh() async {
    for (final i in _loaded) {
      switch (i) {
        case 0:
          ref.invalidate(assignmentsProvider(_id));
          break;
        case 1:
          ref.invalidate(quizzesProvider(_id));
          break;
        case 2:
          ref.invalidate(progressProvider(_id));
          break;
        case 3:
          ref.invalidate(attendanceProvider(_id));
          break;
        case 4:
          ref.invalidate(notificationsProvider(_id));
          break;
      }
    }
    // Give the spinners a chance to render.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            _Header(student: widget.student),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _LazySection(
                    index: 0,
                    icon: Icons.assignment_outlined,
                    label: 'Assignments',
                    color: const Color(0xFF1E88E5),
                    onOpen: () => _loaded.add(0),
                    builder: (ctx) => _AssignmentsBody(studentId: _id),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _LazySection(
                    index: 1,
                    icon: Icons.quiz_outlined,
                    label: 'Quizzes & Exams',
                    color: const Color(0xFFE8A838),
                    onOpen: () => _loaded.add(1),
                    builder: (ctx) => _QuizzesBody(studentId: _id),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _LazySection(
                    index: 2,
                    icon: Icons.bar_chart_rounded,
                    label: 'Progress Report',
                    color: const Color(0xFF27AE60),
                    onOpen: () => _loaded.add(2),
                    builder: (ctx) => _ProgressBody(studentId: _id),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _LazySection(
                    index: 3,
                    icon: Icons.event_available_outlined,
                    label: 'Attendance',
                    color: const Color(0xFF9B59B6),
                    onOpen: () => _loaded.add(3),
                    builder: (ctx) => _AttendanceBody(studentId: _id),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _LazySection(
                    index: 4,
                    icon: Icons.notifications_outlined,
                    label: 'Activity Feed',
                    color: AppColors.primary,
                    onOpen: () => _loaded.add(4),
                    builder: (ctx) => _ActivityBody(studentId: _id),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Pull down to refresh.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── Header ────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.student});
  final LinkedStudent student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
              gradient: AppColors.authBackgroundGradient),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  backgroundImage:
                      (student.avatarUrl?.isNotEmpty ?? false)
                          ? NetworkImage(student.avatarUrl!)
                          : null,
                  child: (student.avatarUrl?.isNotEmpty ?? false)
                      ? null
                      : Text(
                          student.name.isNotEmpty
                              ? student.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(student.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
                if (student.grade?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(_grade(student.grade!),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _grade(String raw) {
    final t = raw.trim();
    if (t.toLowerCase().startsWith('grade')) return t;
    return 'Grade $t';
  }
}

// ────────────────────────── Lazy section shell ─────────────────────────────

class _LazySection extends StatefulWidget {
  const _LazySection({
    required this.index,
    required this.icon,
    required this.label,
    required this.color,
    required this.onOpen,
    required this.builder,
  });

  final int index;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onOpen;
  final WidgetBuilder builder;

  @override
  State<_LazySection> createState() => _LazySectionState();
}

class _LazySectionState extends State<_LazySection> {
  bool _open = false;

  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open) widget.onOpen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(widget.icon, color: widget.color),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(widget.label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more_rounded,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    child: widget.builder(context),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── Section bodies ────────────────────────────────

class _AssignmentsBody extends ConsumerWidget {
  const _AssignmentsBody({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assignmentsProvider(studentId));
    return async.when(
      loading: () => const SectionLoading(),
      error: (e, _) => SectionError(
          error: e,
          onRetry: () => ref.invalidate(assignmentsProvider(studentId))),
      data: (items) => items.isEmpty
          ? const SectionEmpty(
              icon: Icons.assignment_outlined, label: 'No assignments yet.')
          : Column(
              children: items.map((a) => AssignmentCard(item: a)).toList()),
    );
  }
}

class _QuizzesBody extends ConsumerWidget {
  const _QuizzesBody({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(quizzesProvider(studentId));
    return async.when(
      loading: () => const SectionLoading(),
      error: (e, _) => SectionError(
          error: e,
          onRetry: () => ref.invalidate(quizzesProvider(studentId))),
      data: (items) => items.isEmpty
          ? const SectionEmpty(
              icon: Icons.quiz_outlined, label: 'No quizzes yet.')
          : Column(children: items.map((q) => QuizCard(item: q)).toList()),
    );
  }
}

class _ProgressBody extends ConsumerWidget {
  const _ProgressBody({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(progressProvider(studentId));
    return async.when(
      loading: () => const SectionLoading(),
      error: (e, _) => SectionError(
          error: e,
          onRetry: () => ref.invalidate(progressProvider(studentId))),
      data: (report) => ProgressSummary(report: report),
    );
  }
}

class _AttendanceBody extends ConsumerWidget {
  const _AttendanceBody({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceProvider(studentId));
    return async.when(
      loading: () => const SectionLoading(),
      error: (e, _) => SectionError(
          error: e,
          onRetry: () => ref.invalidate(attendanceProvider(studentId))),
      data: (data) {
        if (data.records.isEmpty && data.summary.total == 0) {
          return const SectionEmpty(
              icon: Icons.event_busy_outlined,
              label: 'No attendance records.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceSummaryRow(summary: data.summary),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.xs),
            ...data.records
                .map((r) => AttendanceRecordTile(record: r))
                .toList(),
          ],
        );
      },
    );
  }
}

class _ActivityBody extends ConsumerWidget {
  const _ActivityBody({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider(studentId));
    return async.when(
      loading: () => const SectionLoading(),
      error: (e, _) => SectionError(
          error: e,
          onRetry: () =>
              ref.invalidate(notificationsProvider(studentId))),
      data: (items) => items.isEmpty
          ? const SectionEmpty(
              icon: Icons.notifications_none_rounded,
              label: 'No activity yet.')
          : Column(
              children: items
                  .map((n) => ActivityNotificationCard(
                      studentId: studentId, item: n))
                  .toList(),
            ),
    );
  }
}
