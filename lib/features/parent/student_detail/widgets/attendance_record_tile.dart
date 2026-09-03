import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_spacing.dart';
import '../models/attendance.dart';

class AttendanceRecordTile extends StatelessWidget {
  const AttendanceRecordTile({super.key, required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = record.dateTime;
    final dateLabel = dt != null ? DateFormat('MMM d').format(dt) : record.date;

    IconData icon;
    Color color;
    switch (record.status) {
      case 'absent':
        icon = Icons.cancel_rounded;
        color = const Color(0xFFC62828);
        break;
      case 'late':
        icon = Icons.schedule_rounded;
        color = const Color(0xFFE65100);
        break;
      case 'present':
      default:
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF2E7D32);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.subjectName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(dateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55))),
              ],
            ),
          ),
          Text(record.status[0].toUpperCase() + record.status.substring(1),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}
