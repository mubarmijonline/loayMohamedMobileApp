import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_palette.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../providers.dart';

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key, this.type});
  final String? type; // 'homework' | 'quiz' | null
  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  late String? _type = widget.type;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(assignmentsProvider(_type));
    return Scaffold(
      appBar: AppBar(
        title: Text(_type == 'quiz' ? 'Quizzes' : 'Assignments'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _type == null,
                  onTap: () => setState(() => _type = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Homework',
                  selected: _type == 'homework',
                  onTap: () => setState(() => _type = 'homework'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Quiz',
                  selected: _type == 'quiz',
                  onTap: () => setState(() => _type = 'quiz'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () async => ref.refresh(assignmentsProvider(_type).future),
        child: list.when(
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
              onRetry: () => ref.invalidate(assignmentsProvider(_type)),
            ),
          ),
          data: (items) => items.isEmpty
              ? const CenteredScroll(
                  child: EmptyState(
                    title: 'Nothing here',
                    message: 'You have no items in this category.',
                    icon: Icons.assignment_outlined,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _AssignmentTile(item: items[i]),
                ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    // The selected chip used brand navy for its label on a navy-tinted fill,
    // so in dark mode the active filter read as a bare checkmark with no
    // word beside it — the opposite of the intended emphasis.
    final active =
        context.palette.isDark ? AppColors.accent : AppColors.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor:
          active.withValues(alpha: context.palette.isDark ? 0.22 : 0.10),
      checkmarkColor: active,
      labelStyle: TextStyle(
        color: selected
            ? active
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

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
          if (item.subjectName != null) ...[
            const SizedBox(height: 4),
            Text(
              item.subjectName!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ],
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
