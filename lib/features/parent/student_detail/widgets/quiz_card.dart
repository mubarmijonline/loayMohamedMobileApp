import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../models/quiz.dart';

class QuizCard extends StatelessWidget {
  const QuizCard({super.key, required this.item});
  final Quiz item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = item.dueDate != null
        ? DateFormat('MMM d').format(item.dueDate!)
        : '—';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.quiz_outlined,
                  color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
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
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6))),
                ],
              ),
            ),
            _ScoreChip(item: item),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.item});
  final Quiz item;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    if (item.grade != null) {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
      label = '${item.grade} / ${item.maxGrade ?? '–'}';
    } else if (item.status == 'submitted') {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      label = 'Submitted';
    } else {
      bg = const Color(0xFFECEFF1);
      fg = const Color(0xFF455A64);
      label = 'Upcoming';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
