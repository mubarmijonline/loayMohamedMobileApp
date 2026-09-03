import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../providers.dart';

class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(subjectProvider(subjectId)).valueOrNull;
    final resolvedName = ref.watch(subjectNameProvider(subjectId));
    // Prefer detail (carries grade / progress / lessons) but override its
    // possibly-empty name with the resolved one.
    final subject = detail != null
        ? Subject(
            id: detail.id,
            name: resolvedName ?? detail.name,
            classId: detail.classId,
            description: detail.description,
            coverUrl: detail.coverUrl,
            grade: detail.grade,
            lessonsCount: detail.lessonsCount,
            completionPercent: detail.completionPercent,
            enrollmentStatus: detail.enrollmentStatus,
          )
        : (resolvedName != null
            ? Subject(id: subjectId, name: resolvedName, classId: subjectId)
            : null);
      final playbackClassId =
        (subject?.classId?.trim().isNotEmpty ?? false)
          ? subject!.classId!
          : subjectId;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        body: Column(
          children: [
            _SubjectHero(subject: subject, subjectId: subjectId),
            const _SubjectTabBar(),
            Expanded(
              child: TabBarView(
                children: [
                  _ContentTab(
                    subjectId: subjectId,
                    playbackClassId: playbackClassId,
                  ),
                  _AssignmentsTab(subjectId: subjectId, type: 'homework'),
                  _AssignmentsTab(subjectId: subjectId, type: 'quiz'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Hero header ─────────────────────────────

class _SubjectHero extends ConsumerWidget {
  const _SubjectHero({required this.subject, required this.subjectId});
  final Subject? subject;
  final String subjectId;

  Color _progressColor(int pct) {
    if (pct >= 100) return const Color(0xFF14B8A6);
    if (pct >= 75) return const Color(0xFF22C55E);
    if (pct >= 50) return const Color(0xFFF59E0B);
    if (pct >= 25) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight - 8;
    final name = subject?.name ?? 'Subject';
    final grade = subject?.grade;
    // The detail endpoint sometimes omits `lessons_count`. Fall back to the
    // length of the actual lessons list (which the screen already loads in
    // _ContentTab) so the hero chip never reads "0 lessons" when the subject
    // really does have lessons.
    final lessonsList =
        ref.watch(lessonsProvider(subjectId)).valueOrNull;
    final declaredCount = subject?.lessonsCount ?? 0;
    final lessons = declaredCount > 0
        ? declaredCount
        : (lessonsList?.length ?? 0);
    final workload =
        ref.watch(subjectWorkloadProvider).valueOrNull?[subjectId];
    final grandTotal = workload?.grandTotal ?? 0;
    final done = workload == null
        ? 0
        : (workload.assignmentsTotal - workload.assignmentsPending) +
            (workload.quizzesTotal - workload.quizzesPending);
    final overall = grandTotal == 0 ? 0.0 : done / grandTotal;
    final overallPct = (overall * 100).round();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        topPad,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x335E47F2),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT SUBJECT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (grade != null && grade.isNotEmpty)
                _HeroChip(icon: Icons.school_rounded, label: grade),
              if (lessons > 0)
                _HeroChip(
                  icon: Icons.menu_book_rounded,
                  label: '$lessons lessons',
                ),
            ],
          ),
          if (grandTotal > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 6,
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.18),
                      valueColor:
                          AlwaysStoppedAnimation(_progressColor(overallPct)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$overallPct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$done of $grandTotal tasks completed',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Tab bar ─────────────────────────────

class _SubjectTabBar extends StatelessWidget {
  const _SubjectTabBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surface
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: isDark
            ? Border.all(color: scheme.outline.withValues(alpha: 0.35))
            : null,
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: TabBar(
        isScrollable: false,
        labelColor: Colors.white,
        unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.65),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        tabs: const [
          Tab(text: 'Videos'),
          Tab(text: 'Assignments'),
          Tab(text: 'Quizzes'),
        ],
      ),
    );
  }
}

// ───────────────────────────── Content tab ─────────────────────────────

class _ContentTab extends ConsumerWidget {
  const _ContentTab({
    required this.subjectId,
    required this.playbackClassId,
  });
  final String subjectId;
  final String playbackClassId;

  /// Resolve a human-friendly *topic* name for a Library entry.
  ///
  /// Priority:
  ///   1. The parent lesson's title (looked up by `lessonId`).
  ///   2. The content's `description` if it looks like a sentence rather
  ///      than a filename.
  ///   3. The raw `content.title` with any `"<Subject> — "` /
  ///      `"<anything> - "` prefix stripped off.
  String _libraryTitle(
    ContentItem c, {
    required Map<String, String> lessonTitleById,
    String? subjectName,
  }) {
    final lessonId = c.lessonId;
    if (lessonId != null) {
      final lt = lessonTitleById[lessonId]?.trim() ?? '';
      if (lt.isNotEmpty) return lt;
    }
    final desc = c.description?.trim() ?? '';
    if (desc.isNotEmpty && desc.length <= 80 && desc.contains(' ')) {
      return desc;
    }
    final raw = c.title.trim();
    if (raw.isEmpty) return raw;
    final normalizedSubject = subjectName?.trim() ?? '';
    if (normalizedSubject.isNotEmpty) {
      for (final sep in [' — ', ' - ', ' – ', ': ']) {
        final prefix = '$normalizedSubject$sep';
        if (raw.toLowerCase().startsWith(prefix.toLowerCase())) {
          final cleaned = raw.substring(prefix.length).trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
    }
    return raw;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectName = ref.watch(subjectNameProvider(subjectId));
    final lessons = ref.watch(lessonsProvider(subjectId));
    final contents = ref.watch(contentsProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(lessonsProvider(subjectId));
        ref.invalidate(contentsProvider);
        await ref.read(lessonsProvider(subjectId).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          // Lessons
          lessons.when(
            loading: () => Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SkeletonBox(height: 72, radius: AppRadius.lg),
                ),
              ),
            ),
            error: (e, _) => ErrorStateView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () => ref.invalidate(lessonsProvider(subjectId)),
            ),
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.isNotEmpty) ...[
                  const SectionHeader(title: 'Lessons'),
                  ...items.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _LessonTile(
                        lesson: l,
                        subjectId: playbackClassId,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
          // Loose content
          contents.when(
            loading: () => Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SkeletonBox(height: 72, radius: AppRadius.lg),
                ),
              ),
            ),
            error: (e, _) => ErrorStateView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () => ref.invalidate(contentsProvider),
            ),
            data: (items) {
              final filtered = items
                  .where((c) =>
                      c.subjectId == subjectId ||
                      c.className == subjectName,)
                  .toList();
              if (filtered.isEmpty && lessons.valueOrNull?.isEmpty == true) {
                return const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyState(
                    title: 'No content yet',
                    message: 'Content for this subject will appear here.',
                    icon: Icons.video_library_outlined,
                  ),
                );
              }
              if (filtered.isEmpty) return const SizedBox.shrink();
              final lessonTitleById = <String, String>{
                for (final l in (lessons.valueOrNull ?? const <Lesson>[]))
                  l.id: l.title,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Library'),
                  const SizedBox(height: AppSpacing.sm),
                  ...filtered.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ContentTile(
                        content: c,
                        subjectId: playbackClassId,
                        displayTitle: _libraryTitle(
                          c,
                          lessonTitleById: lessonTitleById,
                          subjectName: subjectName,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Assignments / Quizzes tab ─────────────────────────────

class _AssignmentsTab extends ConsumerWidget {
  const _AssignmentsTab({required this.subjectId, required this.type});
  final String subjectId;
  final String type; // 'homework' | 'quiz'

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = type == 'quiz'
        ? ref.watch(quizzesProvider)
        : ref.watch(assignmentsProvider(type));
    final subjectName = ref.watch(subjectNameProvider(subjectId));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        if (type == 'quiz') {
          ref.invalidate(quizzesProvider);
          await ref.read(quizzesProvider.future);
        } else {
          ref.invalidate(assignmentsProvider(type));
          await ref.read(assignmentsProvider(type).future);
        }
      },
      child: source.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: List.generate(
            4,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: SkeletonBox(height: 96, radius: AppRadius.lg),
            ),
          ),
        ),
        error: (e, _) => CenteredScroll(
          child: ErrorStateView(
            message: e is AppFailure ? e.message : e.toString(),
            onRetry: () => type == 'quiz'
                ? ref.invalidate(quizzesProvider)
                : ref.invalidate(assignmentsProvider(type)),
          ),
        ),
        data: (items) {
          final filtered = items
              .where((a) =>
                  a.subjectId == subjectId ||
                  (subjectName != null && a.subjectName == subjectName),)
              .toList();
          if (filtered.isEmpty) {
            return CenteredScroll(
              child: EmptyState(
                title: type == 'quiz' ? 'No quizzes yet' : 'No assignments yet',
                message: 'Items for this subject will appear here.',
                icon: type == 'quiz'
                    ? Icons.quiz_outlined
                    : Icons.assignment_outlined,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: filtered.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _AssignmentTile(item: filtered[i]),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Tiles ─────────────────────────────

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.item});
  final Assignment item;

  Color _statusColor() {
    if (item.status == 'graded') return AppColors.success;
    if (item.status == 'submitted') return AppColors.info;
    if (item.isOverdue) return AppColors.danger;
    return AppColors.warning;
  }

  String _statusLabel() {
    if (item.status == 'graded') {
      return item.score != null && item.maxScore != null
          ? 'GRADED · ${item.score}/${item.maxScore}'
          : 'GRADED';
    }
    if (item.status == 'submitted') return 'SUBMITTED';
    if (item.isOverdue) return 'OVERDUE';
    return 'DUE';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = item.dueAt;
    return PremiumCard(
      onTap: () => Navigator.of(context).pushNamed('/assignments/${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.title, style: theme.textTheme.titleSmall),
              ),
              StatusChip(label: _statusLabel(), color: _statusColor()),
            ],
          ),
          if (due != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),),
                const SizedBox(width: 4),
                Text(
                  'Due ${DateFormat.yMMMd().add_jm().format(due)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({
    required this.content,
    required this.subjectId,
    required this.displayTitle,
  });
  final ContentItem content;
  final String subjectId;
  final String displayTitle;

  IconData _iconFor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'article':
        return Icons.article_rounded;
      case 'video':
      default:
        return Icons.play_circle_fill_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return 'PDF';
      case 'article':
        return 'Article';
      case 'video':
      default:
        return 'Video';
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '$m min';
    final s = d.inSeconds;
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurfaceSoft = scheme.onSurface.withValues(alpha: 0.65);
    final typeLabel = _typeLabel(content.type);
    final durationLabel =
        content.duration != null && content.duration! > Duration.zero
            ? _formatDuration(content.duration!)
            : null;

    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () {
        Navigator.of(context).pushNamed(
          '/player',
          arguments: {
            'contentId': content.id,
            'lessonId': content.lessonId,
            'subjectId': subjectId,
            'title': displayTitle,
          },
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _iconFor(content.type),
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaPill(
                      icon: _iconFor(content.type),
                      label: typeLabel,
                    ),
                    if (durationLabel != null)
                      _MetaPill(
                        icon: Icons.schedule_rounded,
                        label: durationLabel,
                      ),
                    if (content.watched)
                      const _MetaPill(
                        icon: Icons.check_circle_rounded,
                        label: 'Watched',
                        color: AppColors.success,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            color: onSurfaceSoft,
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    this.color,
  });
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.70);
    final bg = (color ?? theme.colorScheme.primary).withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.subjectId});
  final Lesson lesson;
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumCard(
      onTap: !lesson.unlocked
          ? null
          : () {
              if (lesson.contents.isNotEmpty) {
                final c = lesson.contents.first;
                Navigator.of(context).pushNamed(
                  '/player',
                  arguments: {
                    'contentId': c.id,
                    'lessonId': lesson.id,
                    'subjectId': subjectId,
                    'title': c.title,
                  },
                );
              }
            },
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              lesson.unlocked
                  ? Icons.play_circle_fill_rounded
                  : Icons.lock_outline_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.title, style: theme.textTheme.titleSmall),
                Text(
                  '${lesson.contents.length} item${lesson.contents.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
        ],
      ),
    );
  }
}
