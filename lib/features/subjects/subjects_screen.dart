import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(enrolledSubjectsProvider);
    final enrollments = ref.watch(enrollmentsProvider);
    final suggested = ref.watch(suggestedSubjectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Subjects')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(enrolledSubjectsProvider);
          ref.invalidate(subjectsProvider);
          ref.invalidate(enrollmentsProvider);
          ref.invalidate(subjectWorkloadProvider);
          ref.invalidate(suggestedSubjectsProvider);
          await ref.read(enrolledSubjectsProvider.future);
        },
        color: AppColors.secondary,
        child: subjects.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: const [
              SkeletonBox(height: 110, radius: AppRadius.lg),
              SizedBox(height: 12),
              SkeletonBox(height: 110, radius: AppRadius.lg),
              SizedBox(height: 12),
              SkeletonBox(height: 110, radius: AppRadius.lg),
            ],
          ),
          error: (e, _) => CenteredScroll(
            child: ErrorStateView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () => ref.invalidate(enrolledSubjectsProvider),
            ),
          ),
          data: (items) {
            final enrollMap = <String, Enrollment>{
              for (final e in (enrollments.value ?? const <Enrollment>[]))
                e.subjectId: e,
            };
            final suggestedItems = suggested.value ?? const <Subject>[];
            // Hide subjects already in the enrolled list, in case the
            // backend hasn't filtered them out yet.
            final enrolledIds = items.map((s) => s.id).toSet();
            final suggestedFiltered = suggestedItems
                .where((s) => !enrolledIds.contains(s.id))
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _SubjectsHeader(count: items.length),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  const _EmptySubjectPlaceholder()
                else
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    _SubjectCard(
                      subject: items[i],
                      enrollment: enrollMap[items[i].id],
                    ),
                  ],
                if (suggestedFiltered.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SuggestedHeader(count: suggestedFiltered.length),
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < suggestedFiltered.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    _SubjectCard(
                      subject: suggestedFiltered[i],
                      enrollment: enrollMap[suggestedFiltered[i].id],
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Header for the "Suggested for your grade" section. Hidden when no
/// suggestions are available (we never render this widget in that case).
class _SuggestedHeader extends ConsumerWidget {
  const _SuggestedHeader({required this.count});
  final int count;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authControllerProvider).user;
    final grade = user?.grade;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suggested for you',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (grade != null && grade.toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Available subjects for grade $grade',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.onSurface.withValues(alpha: 0.15)
                : AppColors.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: isDark ? scheme.onSurface : AppColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubjectsHeader extends StatelessWidget {
  const _SubjectsHeader({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Text(
          'My subjects',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.onSurface.withValues(alpha: 0.15)
                : AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: isDark ? scheme.onSurface : AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySubjectPlaceholder extends StatelessWidget {
  const _EmptySubjectPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.4),
          width: 1.2,
        ),
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
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No subjects yet',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your enrolled subjects will appear here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contact your instructor to be enrolled in a subject. New subjects will show up here automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.85),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends ConsumerStatefulWidget {
  const _SubjectCard({required this.subject, required this.enrollment});
  final Subject subject;
  final Enrollment? enrollment;

  @override
  ConsumerState<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends ConsumerState<_SubjectCard> {
  bool _expanded = false;

  Subject get subject => widget.subject;
  Enrollment? get enrollment => widget.enrollment;

  Color _statusColor(String? status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.danger;
      default:
        return Colors.grey.shade500;
    }
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('math')) return Icons.functions_rounded;    if (n.contains('phys')) return Icons.science_rounded;
    if (n.contains('chem')) return Icons.biotech_rounded;
    if (n.contains('bio')) return Icons.eco_rounded;
    if (n.contains('eng') || n.contains('lang')) {
      return Icons.translate_rounded;
    }
    if (n.contains('arab')) return Icons.menu_book_rounded;
    if (n.contains('hist')) return Icons.history_edu_rounded;
    if (n.contains('geo')) return Icons.public_rounded;
    if (n.contains('comp') || n.contains('it') || n.contains('cs')) {
      return Icons.code_rounded;
    }
    return Icons.school_rounded;
  }

  Color _progressColor(int pct) {
    if (pct >= 100) return const Color(0xFF14B8A6);
    if (pct >= 75) return const Color(0xFF22C55E);
    if (pct >= 50) return const Color(0xFFF59E0B);
    if (pct >= 25) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status =
        enrollment?.status ?? subject.enrollmentStatus ?? 'active';
    final isActive = status == 'active';
    final workload =
        ref.watch(subjectWorkloadProvider).valueOrNull?[subject.id];
    // Overall progress: prefer the workload-derived ratio over the
    // server-supplied completionPercent so it stays accurate when the
    // student finishes homework/quizzes.
    int overallPct;
    if (workload != null && workload.grandTotal > 0) {
      final done = (workload.assignmentsTotal - workload.assignmentsPending) +
          (workload.quizzesTotal - workload.quizzesPending);
      overallPct = ((done / workload.grandTotal) * 100).round();
    } else {
      overallPct =
          ((subject.completionPercent ?? 0).clamp(0, 1) * 100).round();
    }
    final pct = overallPct;

    return PremiumCard(
      onTap: () =>
          Navigator.of(context).pushNamed('/subjects/${subject.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      AppColors.secondary.withValues(alpha: 0.18),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  _iconFor(subject.name),
                  color: AppColors.primary,
                  size: 26,
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (subject.grade != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Grade ${subject.grade}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!isActive && status.isNotEmpty)
                StatusChip(
                  label: status.toUpperCase(),
                  color: _statusColor(status),
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
            ],
          ),
          if (subject.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              subject.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _MiniStat(
                icon: Icons.play_circle_outline_rounded,
                value: '${subject.lessonsCount ?? 0}',
                label: 'Lessons',
              ),
              const SizedBox(width: 8),
              // Toggle for the homework + quiz extra info.
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded ? 'Hide' : 'HW & Quizzes',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        _MiniStat(
                          icon: Icons.assignment_outlined,
                          value: workload == null
                              ? '0'
                              : '${workload.assignmentsTotal - workload.assignmentsPending}/${workload.assignmentsTotal}',
                          label: 'HW',
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          icon: Icons.quiz_outlined,
                          value: workload == null
                              ? '0'
                              : '${workload.quizzesTotal - workload.quizzesPending}/${workload.quizzesTotal}',
                          label: 'Quizzes',
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (pct > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                backgroundColor:
                    scheme.onSurface.withValues(alpha: 0.08),
                color: _progressColor(pct),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$pct% complete',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _progressColor(pct),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: scheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(text: value),
                      TextSpan(
                        text: ' $label',
                        style: TextStyle(
                          color:
                              scheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
