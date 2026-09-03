import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../models/progress.dart';

class ProgressSummary extends StatelessWidget {
  const ProgressSummary({super.key, required this.report});
  final ProgressReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 160,
          width: 160,
          child: CustomPaint(
            painter:
                _GaugePainter(percent: report.overallPercent ?? 0, hasData: report.overallPercent != null),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    report.overallPercent != null
                        ? '${report.overallPercent!.toStringAsFixed(1)}%'
                        : '—',
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary),
                  ),
                  Text('Overall',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (report.subjects.isEmpty)
          Text('No subjects yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6)))
        else
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: report.subjects.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, i) =>
                  _SubjectProgressCard(item: report.subjects[i]),
            ),
          ),
      ],
    );
  }
}

class _SubjectProgressCard extends StatelessWidget {
  const _SubjectProgressCard({required this.item});
  final SubjectProgress item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (item.gradePercent ?? 0).clamp(0, 100) / 100;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.primarySurface,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.gradePercent != null
                ? '${item.gradePercent!.toStringAsFixed(1)}%'
                : '—',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.event_busy_outlined,
                  size: 14,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text('Absences: ${item.absenceCount}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.percent, required this.hasData});
  final double percent;
  final bool hasData;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final track = Paint()
      ..color = AppColors.primarySurface
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = hasData ? AppColors.primary : Colors.transparent
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    final sweep = (percent.clamp(0, 100) / 100) * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.hasData != hasData;
}
