import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/assets.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';
import '../../core/design/app_palette.dart';

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
      // No top SafeArea: the header paints under the status bar deliberately,
      // and applies the inset itself.
      body: RefreshIndicator(
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
            SliverToBoxAdapter(
              child: _HomeHeader(
                greeting: greeting,
                name: user?.name ?? 'Student',
                // Null while loading, so the greeting still paints at once.
                dashboard: dash.valueOrNull,
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.lg),
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
                  sliver: SliverToBoxAdapter(child: _DashboardSkeleton()),
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
                              onPressed: () =>
                                  Navigator.of(context).pushNamed('/subjects'),
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
    );
  }
}

// ───────────────────────────── Hero ─────────────────────────────

/// Full-bleed brand header: greeting, portrait, and the progress band.
///
/// The portrait sits *behind* the content and runs up under the status bar,
/// which is what makes it read as part of the app's chrome rather than a
/// picture that has been dropped on top of the page.
///
/// It also merges the overall-progress band into itself. An earlier attempt
/// put the portrait in its own banner above that band, which left two
/// full-width navy blocks stacked at the top — heavy, repetitive, and it
/// pushed the real content off the first screen. One navy region carries both.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.name,
    this.dashboard,
  });

  final String greeting;
  final String name;

  /// Null while the dashboard is still loading; the greeting renders anyway so
  /// the header never pops in late.
  final StudentDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final topInset = MediaQuery.paddingOf(context).top;
    final data = dashboard;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The header is navy under both themes, so the status bar always needs
      // light content over it. Without this the light theme painted a
      // near-black clock and battery on navy.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B2A44), Color(0xFF0B1426)],
                  ),
                ),
              ),
            ),

            // Anchored to the top-right and allowed to run under the status bar.
            Positioned(
              // Not 0: at the very top the crop cut straight through his
              // forehead. The navy still runs under the status bar; only the
              // photograph starts below it.
              top: topInset * 0.5,
              right: 0,
              bottom: 0,
              width: 150,
              child: Image.asset(
                AppAssets.heroFor(width),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                // A missing asset must never blank the header.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

            // Readability scrim. JUSTIFIED GRADIENT: this is what keeps the
            // greeting and the stats legible where they cross the photograph.
            // It is not decoration, and it is why the portrait can sit behind
            // live content at all.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF16233A),
                      const Color(0xFF16233A).withValues(alpha: 0.92),
                      const Color(0xFF16233A).withValues(alpha: 0.55),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                topInset + 10,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AvatarInitials(name: name, size: 44),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              greeting,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const _CircleIconButton(
                        icon: Icons.search_rounded,
                        onDark: true,
                      ),
                    ],
                  ),
                  if (data != null) ...[
                    // The band is a separate idea from the greeting; at md it
                    // read as one crowded block with the student's name.
                    const SizedBox(height: AppSpacing.lg),
                    _OverviewBand(dashboard: data, flat: true),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    this.onTap,
    this.onDark = false,
  });
  final IconData icon;
  final VoidCallback? onTap;

  /// True when the button sits on the brand-navy banner, which is navy in
  /// both themes — so it takes a translucent white treatment rather than the
  /// themed surface colour.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = onDark ? Colors.white.withValues(alpha: 0.16) : scheme.surface;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.24)
        : scheme.outline.withValues(alpha: 0.4);
    final fg = onDark ? Colors.white : scheme.onSurface;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap ?? () => Navigator.of(context).pushNamed('/subjects'),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
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
              // The tile is a 12% wash of this colour and the glyph is this
              // colour, so a navy value renders navy-on-navy in dark.
              color:
                  context.palette.isDark ? AppColors.accent : AppColors.primary,
              onTap: () => Navigator.of(context).pushNamed('/subjects'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _StatCard(
              icon: Icons.pending_actions_rounded,
              value: '$pendingTotal',
              label: 'Pending tasks',
              // Neutral. "4 pending" is a count, not a warning, and amber
              // here was the only warm colour on the screen.
              color: pendingTotal == 0
                  ? AppColors.success
                  : context.palette.textSecondary,
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
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
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
  const _OverviewBand({required this.dashboard, this.flat = false});
  final StudentDashboard dashboard;

  /// Drop the navy container and shadow, because the caller already painted
  /// them. Used by [_HomeHeader], which merges this band into the header so
  /// the page has one navy region instead of two stacked ones.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Prefer the server-supplied overall completion. If it's 0 (or the API
    // didn't send one), fall back to a locally-computed ratio so the ring
    // reflects real progress instead of always reading 0%.
    final hwDone = dashboard.assignmentCount - dashboard.pendingAssignments;
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
      padding: flat ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: flat
          ? null
          : BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B2A44), Color(0xFF0B1426)],
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: context.palette.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
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
                          _progressColorOnDark(pct),
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
              valueColor: AlwaysStoppedAnimation(_progressColorOnDark(pct)),
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

  /// Progress on this band's **dark** navy card.
  ///
  /// Must be light. The obvious "use the brand colour" answer would paint
  /// navy on navy and vanish — which is exactly how the stat card broke once
  /// before.
  Color _progressColorOnDark(int pct) {
    if (pct >= 75) return AppColors.success;
    if (pct == 0) return Colors.white.withValues(alpha: 0.35);
    return Colors.white;
  }

  /// Progress on **light** surfaces.
  ///
  /// One hue plus neutrals: navy while in progress, emerald once genuinely
  /// finished, grey at zero. No accent and no orange — the old five-step
  /// red/orange/amber/green ramp made a card change character as the student
  /// worked through it, and the percentage beside it already says how far
  /// along they are.
  Color _progressColor(BuildContext context, int pct) {
    if (pct >= 75) return AppColors.success;
    if (pct == 0) return context.palette.textHint;
    // Navy is the light-mode "in progress" neutral. On a dark navy card it is
    // invisible — this is what made "63% complete" unreadable — so dark uses
    // the brand cyan for the same meaning.
    return context.palette.isDark ? AppColors.accent : AppColors.primary;
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
            child: Icon(icon, size: 18, color: Colors.white),
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
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
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
            // Progress is one fill on a neutral track. It used to be green
            // butted against orange across the full width, which read as two
            // competing values rather than one measure, and made every card
            // shout.
            child: total == 0
                ? Container(color: context.palette.divider)
                : Row(
                    children: [
                      Expanded(
                        flex: math.max(1, (doneRatio * 1000).round()),
                        child: Container(color: AppColors.success),
                      ),
                      Expanded(
                        flex: math.max(1, ((1 - doneRatio) * 1000).round()),
                        child: Container(color: context.palette.divider),
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

    final aDone = (w.assignmentsTotal - w.assignmentsPending)
        .clamp(0, w.assignmentsTotal);
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
                  // The lavender gradient is a light-mode tint; on a dark card
                  // it is the brightest thing on screen. Dark gets a tinted
                  // navy tile with the accent glyph instead.
                  gradient: context.palette.isDark
                      ? null
                      : AppColors.lavenderGradient,
                  color: context.palette.isDark
                      ? context.palette.surfaceTinted
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: context.palette.isDark
                      ? Border.all(
                          color: AppColors.accent.withValues(alpha: 0.28),
                        )
                      : null,
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: context.palette.isDark
                      ? AppColors.accent
                      : AppColors.primary,
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
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
                      ? context.palette.divider.withValues(alpha: 0.6)
                      : (allDone
                          ? AppColors.success.withValues(alpha: 0.12)
                          : context.palette.textSecondary
                              .withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  grandTotal == 0
                      ? 'No tasks'
                      : (allDone ? 'All done' : '$pendingTotal pending'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: grandTotal == 0
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65)
                        : (allDone
                            ? AppColors.success
                            : context.palette.textSecondary),
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
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? 'Hide assignments & quizzes'
                          : 'Show assignments & quizzes',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
    if (pct >= 75) return AppColors.success;
    if (pct == 0) return context.palette.textHint;
    // Navy is the light-mode "in progress" neutral. On a dark navy card it is
    // invisible — this is what made "63% complete" unreadable — so dark uses
    // the brand cyan for the same meaning.
    return context.palette.isDark ? AppColors.accent : AppColors.primary;
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
