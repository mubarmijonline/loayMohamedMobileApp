import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final user = ref.watch(authControllerProvider).user;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      // Use the theme's scaffold colour so dark mode is honoured.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future).catchError(
                  (_) => const StudentDashboard(
                    subjects: [],
                    overallCompletion: 0,
                  ),
                );
          },
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                sliver: SliverToBoxAdapter(
                  child: _Hero(
                    greeting: greeting,
                    name: user?.name ?? 'Student',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  AppSpacing.xl,
                ),
                sliver: dash.when(
                  loading: () => const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    sliver:
                        SliverToBoxAdapter(child: _DashboardSkeleton()),
                  ),
                  error: (e, _) => SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    sliver: SliverToBoxAdapter(
                      child: ErrorStateView(
                        message: e is AppFailure ? e.message : e.toString(),
                        onRetry: () => ref.invalidate(dashboardProvider),
                      ),
                    ),
                  ),
                  data: (data) {
                    return SliverList.list(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: _OverviewBand(dashboard: data)
                              .animate()
                              .fadeIn(duration: 320.ms),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: _StatRow(dashboard: data)
                              .animate()
                              .fadeIn(duration: 320.ms),
                        ),
                        if (data.subjects.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: SectionHeader(
                              title: 'Your subjects',
                              action: TextButton(
                                onPressed: () => Navigator.of(context)
                                    .pushNamed('/subjects'),
                                child: const Text('See all'),
                              ),
                            ),
                          ),
                          ...data.subjects.map(
                            (s) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.sm,
                              ),
                              child: _SubjectWorkloadCard(
                                subject: s,
                                onTap: () => Navigator.of(context)
                                    .pushNamed('/subjects/${s.id}'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Hero ─────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.name});
  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AvatarInitials(name: name, size: 46),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greeting,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _CircleIconButton(
          icon: Icons.search_rounded,
          onTap: () => Navigator.of(context).pushNamed('/subjects'),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
  });
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Stat row (2 KPI cards) ─────────────────────────

class _StatRow extends StatelessWidget {
  const _StatRow({required this.dashboard});
  final StudentDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final totalSubjects = dashboard.subjects.isNotEmpty
        ? dashboard.subjects.length
        : dashboard.enrolledCount;
    final pendingTotal =
        dashboard.pendingAssignments + dashboard.pendingQuizzes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.menu_book_rounded,
              value: '$totalSubjects',
              label: 'Subjects',
              color: AppColors.primary,
              onTap: () => Navigator.of(context).pushNamed('/subjects'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _StatCard(
              icon: Icons.pending_actions_rounded,
              value: '$pendingTotal',
              label: 'Pending tasks',
              color: pendingTotal == 0 ? AppColors.success : AppColors.warning,
              onTap: () => Navigator.of(context).pushNamed('/assignments'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Workload bar (shared) ─────────────────────────────

class _OverviewBand extends StatelessWidget {
  const _OverviewBand({required this.dashboard});
  final StudentDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Prefer the server-supplied overall completion. If it's 0 (or the API
    // didn't send one), fall back to a locally-computed ratio so the ring
    // reflects real progress instead of always reading 0%.
    final hwDone =
        dashboard.assignmentCount - dashboard.pendingAssignments;
    final qzDone = dashboard.quizCount - dashboard.pendingQuizzes;
    final totalTasks = dashboard.assignmentCount + dashboard.quizCount;
    final doneTasks = hwDone + qzDone;
    final localPct = totalTasks == 0 ? 0.0 : doneTasks / totalTasks;
    final progress = dashboard.overallCompletion > 0
        ? dashboard.overallCompletion.clamp(0, 1).toDouble()
        : localPct.clamp(0, 1).toDouble();
    final pct = (progress * 100).round();
    final pendingTotal =
        dashboard.pendingAssignments + dashboard.pendingQuizzes;
    final lessonsCount = dashboard.contentCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A44), Color(0xFF0B1426)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        // Always provide a value so the indicator is static
                        // (no spinning animation when the user has 0%).
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation(
                          _progressColor(pct),
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall progress',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pct >= 100
                          ? 'You finished all your work'
                          : pendingTotal == 0
                              ? 'All caught up — keep watching lessons!'
                              : '$pendingTotal task${pendingTotal == 1 ? '' : 's'} waiting',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Overall progress bar — mirrors the ring's value with the same
          // status color so the user has a quick linear read.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(_progressColor(pct)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _OverviewMetric(
                icon: Icons.menu_book_outlined,
                label: 'Subjects',
                value: '${dashboard.enrolledCount}',
              ),
              _OverviewMetric(
                icon: Icons.play_lesson_outlined,
                label: 'Lessons',
                value: '$lessonsCount',
              ),
              _OverviewMetric(
                icon: Icons.assignment_outlined,
                label: 'Homework',
                value:
                    '${dashboard.assignmentCount - dashboard.pendingAssignments}/${dashboard.assignmentCount}',
              ),
              _OverviewMetric(
                icon: Icons.quiz_outlined,
                label: 'Quizzes',
                value:
                    '${dashboard.quizCount - dashboard.pendingQuizzes}/${dashboard.quizCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Maps a 0–100 percentage to a status color:
  /// red < 25, orange < 50, amber < 75, green ≥ 75 (teal at 100).
  Color _progressColor(int pct) {
    if (pct >= 100) return const Color(0xFF14B8A6); // teal — done
    if (pct >= 75) return const Color(0xFF22C55E); // green
    if (pct >= 50) return const Color(0xFFF59E0B); // amber
    if (pct >= 25) return const Color(0xFFF97316); // orange
    return const Color(0xFFEF4444); // red — just starting
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.accent),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _WorkloadBar extends StatelessWidget {
  const _WorkloadBar({
    required this.label,
    required this.icon,
    required this.done,
    required this.pending,
    required this.color,
  });
  final String label;
  final IconData icon;
  final int done;
  final int pending;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = (done + pending);
    final doneRatio = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$done / $total',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? Container(color: AppColors.divider)
                : Row(
                    children: [
                      Expanded(
                        flex: math.max(1, (doneRatio * 1000).round()),
                        child: Container(color: AppColors.success),
                      ),
                      Expanded(
                        flex: math.max(1, ((1 - doneRatio) * 1000).round()),
                        child: Container(color: AppColors.warning),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ───────────────── Per-subject workload card ─────────────────

class _SubjectWorkloadCard extends ConsumerStatefulWidget {
  const _SubjectWorkloadCard({required this.subject, required this.onTap});
  final Subject subject;
  final VoidCallback onTap;

  @override
  ConsumerState<_SubjectWorkloadCard> createState() =>
      _SubjectWorkloadCardState();
}

class _SubjectWorkloadCardState extends ConsumerState<_SubjectWorkloadCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final theme = Theme.of(context);
    final workloadAsync = ref.watch(subjectWorkloadProvider);
    final w = workloadAsync.maybeWhen(
      data: (m) => m[subject.id] ?? const SubjectWorkload(),
      orElse: () => const SubjectWorkload(),
    );

    final aDone =
        (w.assignmentsTotal - w.assignmentsPending).clamp(0, w.assignmentsTotal);
    final qDone = (w.quizzesTotal - w.quizzesPending).clamp(0, w.quizzesTotal);
    final pendingTotal = w.pendingTotal;
    final grandTotal = w.grandTotal;
    final allDone = grandTotal > 0 && pendingTotal == 0;
    final overall = grandTotal == 0 ? 0.0 : (aDone + qDone) / grandTotal;
    final overallPct = (overall * 100).round();

    return PremiumCard(
      onTap: widget.onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.lavenderGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (grandTotal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${aDone + qDone} of $grandTotal completed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      )
                    else if ((subject.grade?.isNotEmpty ?? false) ||
                        subject.lessonsCount != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (subject.grade?.isNotEmpty ?? false)
                              subject.grade!,
                            if (subject.lessonsCount != null)
                              '${subject.lessonsCount} lessons',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: grandTotal == 0
                      ? AppColors.divider.withValues(alpha: 0.6)
                      : (allDone
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.14)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  grandTotal == 0
                      ? 'No tasks'
                      : (allDone ? 'All done' : '$pendingTotal pending'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: grandTotal == 0
                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
                        : (allDone ? AppColors.success : AppColors.warning),
                  ),
                ),
              ),
            ],
          ),
          if (grandTotal > 0) ...[
            const SizedBox(height: 12),
            // Overall subject progress (combined hw + quiz).
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(
                        _subjectProgressColor(overallPct),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$overallPct%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _subjectProgressColor(overallPct),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Collapsible "Assignments / Quizzes" breakdown — extra info,
            // hidden by default to keep the card compact.
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? 'Hide assignments & quizzes'
                          : 'Show assignments & quizzes',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      children: [
                        const SizedBox(height: 8),
                        _WorkloadBar(
                          label: 'Assignments',
                          icon: Icons.assignment_outlined,
                          done: aDone,
                          pending: w.assignmentsPending,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        _WorkloadBar(
                          label: 'Quizzes',
                          icon: Icons.quiz_outlined,
                          done: qDone,
                          pending: w.quizzesPending,
                          color: AppColors.info,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Color _subjectProgressColor(int pct) {
    if (pct >= 100) return const Color(0xFF14B8A6);
    if (pct >= 75) return const Color(0xFF22C55E);
    if (pct >= 50) return const Color(0xFFF59E0B);
    if (pct >= 25) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }
}

// ───────────────────────────── Skeleton ─────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 240, radius: AppRadius.xl),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 120, radius: AppRadius.xl)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 120, radius: AppRadius.xl)),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 200, radius: AppRadius.xl),
      ],
    );
  }
}
