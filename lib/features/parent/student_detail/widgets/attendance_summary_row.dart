import 'package:flutter/material.dart';

import '../../../../core/design/app_spacing.dart';
import '../models/attendance.dart';

class AttendanceSummaryRow extends StatelessWidget {
  const AttendanceSummaryRow({super.key, required this.summary});
  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _Chip(
                label: 'Present',
                value: summary.present,
                color: const Color(0xFF2E7D32))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
            child: _Chip(
                label: 'Absent',
                value: summary.absent,
                color: const Color(0xFFC62828))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
            child: _Chip(
                label: 'Late',
                value: summary.late,
                color: const Color(0xFFE65100))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
            child: _Chip(
                label: 'Total',
                value: summary.total,
                color: const Color(0xFF455A64))),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 11)),
          ],
        ),
      );
}
