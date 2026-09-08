import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/app_back_button.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../providers.dart';
import '../content_player/content_player_screen.dart';
import '../videos/content_library.dart';
import '../../core/design/app_palette.dart';

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
    final playbackClassId = (subject?.classId?.trim().isNotEmpty ?? false)
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
          // The theme's iconTheme is near-black, which beats foregroundColor
          // and made the default chevron invisible on this navy header.
          leading: const AppBackButton(),
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

  Color _progressColor(BuildContext context, int pct) {
    // One hue plus neutrals. See dashboard_screen._progressColor.
    if (pct >= 75) return AppColors.success;
    if (pct == 0) return context.palette.textHint;
    // Navy is the light-mode "in progress" neutral. On a dark navy card it is
    // invisible — this is what made "63% complete" unreadable — so dark uses
    // the brand cyan for the same meaning.
    return context.palette.isDark ? AppColors.accent : AppColors.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight - 8;
    final name = subject?.name ?? 'Subject';
    final grade = subject?.grade;
    // The subject document often omits `lessons_count`, so fall back to the
    // content actually available for this class.
    //
    // This used to count `/student/subjects/<id>/lessons`, which can never
    // return anything (see BACKEND_FIXES.md item 1) — so the fallback was
    // always zero and every subject open fired a request guaranteed to 403.
    final subjectContent = ref
            .watch(contentsProvider)
            .valueOrNull
            ?.where((c) => c.subjectId == subjectId)
            .length ??
        0;
    final declaredCount = subject?.lessonsCount ?? 0;
    final lessons = declaredCount > 0 ? declaredCount : subjectContent;
    final workload = ref.watch(subjectWorkloadProvider).valueOrNull?[subjectId];
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
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation(
                          _progressColor(context, overallPct)),
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
        color: isDark ? scheme.surface : Colors.white,
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
    final sections = ref.watch(contentSectionsProvider);
    final isEnrolled = ref.watch(isEnrolledInProvider(subjectId));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref
          ..invalidate(contentsProvider)
          ..invalidate(studentClassesProvider)
          ..invalidate(contentSectionsProvider);
        await ref.read(contentSectionsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          // The portal renders one card grid per class, split into named
          // groups. `ContentSection.group` does the grouping; this widget
          // only renders. Neither sorts — `/student/content` already arrives
          // in `(class_id, group_title, order_index, created_at)` order.
          sections.when(
            loading: () => Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SkeletonBox(height: 180, radius: AppRadius.lg),
                ),
              ),
            ),
            error: (e, _) => ErrorStateView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () => ref.invalidate(contentSectionsProvider),
            ),
            data: (all) {
              // Only this subject's class.
              final mine = all
                  .where(
                    (s) =>
                        s.classId == subjectId ||
                        s.classId == playbackClassId ||
                        s.className == subjectName,
                  )
                  .toList();
              return ContentLibrary(
                sections: mine,
                // The screen header already shows the class name; repeating it
                // directly below was pure duplication.
                showClassHeader: false,
                onOpen: (item) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContentPlayerScreen(
                      contentId: item.id,
                      subjectId: item.classId ?? playbackClassId,
                      title: item.title,
                    ),
                  ),
                ),
                // `/student/content` only ever returns content for classes the
                // student is actually in, so an empty list here means one of
                // two very different things. Say which.
                emptyState: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: isEnrolled
                      ? const EmptyState(
                          title: 'No videos yet',
                          message:
                              'Videos for this subject will appear here once '
                              'your teacher publishes them.',
                          icon: Icons.video_library_outlined,
                        )
                      : _NotEnrolledNotice(subjectId: subjectId),
                ),
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
              .where(
                (a) =>
                    a.subjectId == subjectId ||
                    (subjectName != null && a.subjectName == subjectName),
              )
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
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
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
      // No mark until the teacher releases it — an absent grade is not a zero
      // (API_BRIEF §7).
      final grade = item.visibleGrade;
      final max = item.submission?.marking?.totalMax ?? item.maxScore;
      if (item.awaitingRelease) return 'MARKED';
      return grade != null && max != null ? 'GRADED · $grade/$max' : 'GRADED';
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
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
                const SizedBox(width: 4),
                Text(
                  'Due ${DateFormat.yMMMd().add_jm().format(due)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
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
              color: context.palette.surfaceTinted,
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

/// Shown when the API answers `403 not_enrolled` for a subject.
///
/// This is an expected state, not an error: the student is looking at a
/// subject they have not joined. Offer the way forward rather than a retry
/// button that will fail identically every time.
class _NotEnrolledNotice extends ConsumerStatefulWidget {
  const _NotEnrolledNotice({required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<_NotEnrolledNotice> createState() => _NotEnrolledNoticeState();
}

class _NotEnrolledNoticeState extends ConsumerState<_NotEnrolledNotice> {
  bool _busy = false;
  String? _result;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await ref
          .read(studentRepositoryProvider)
          .requestEnrollment(widget.subjectId);
      if (!mounted) return;
      setState(() => _result = 'Request sent. Your teacher will review it.');
      ref.invalidate(enrollmentsProvider);
      ref.invalidate(enrolledSubjectsProvider);
    } catch (e) {
      if (!mounted) return;
      // `already_pending` / `already_enrolled` are informative, not failures.
      final msg = e is AppFailure ? e.message : 'Could not send the request.';
      setState(() => _result = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'You are not enrolled in this subject',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lessons and videos unlock once your teacher approves you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_result != null)
            Text(
              _result!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _request,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Request enrollment'),
            ),
        ],
      ),
    );
  }
}
