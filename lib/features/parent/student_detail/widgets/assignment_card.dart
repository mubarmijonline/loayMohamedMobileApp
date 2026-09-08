import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../models/assignment.dart';
import '../../../../core/design/app_palette.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.item});
  final Assignment item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueLabel = item.dueDate != null
        ? 'Due ${DateFormat('MMM d').format(item.dueDate!)}'
        : 'No due date';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.subject.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 4),
                Text(dueLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7))),
                const Spacer(),
                _StatusChip(item: item),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});
  final Assignment item;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;
    switch (item.status) {
      case 'graded':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        label = '${item.grade ?? '–'} / ${item.maxGrade ?? '–'}';
        break;
      case 'submitted':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        label = 'Submitted';
        break;
      case 'late':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Late';
        break;
      case 'pending':
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
