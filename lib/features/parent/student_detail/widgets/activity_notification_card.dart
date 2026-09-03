import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../models/activity_notification.dart';
import '../providers/notifications_provider.dart';

class ActivityNotificationCard extends ConsumerWidget {
  const ActivityNotificationCard({
    super.key,
    required this.studentId,
    required this.item,
  });

  final String studentId;
  final ActivityNotification item;

  static const _categoryColors = <String, Color>{
    'assignment': Color(0xFF1E88E5),
    'grade': Color(0xFF43A047),
    'attendance': Color(0xFFFB8C00),
    'announcement': Color(0xFF8E24AA),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = _categoryColors[item.category] ?? const Color(0xFF9E9E9E);
    final localRead = ref.watch(notificationLocalReadProvider(studentId));
    final isRead = item.read || localRead.contains(item.id);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: isRead
          ? null
          : () => ref
              .read(notificationLocalReadProvider(studentId).notifier)
              .markRead(item.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.body,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7))),
                  ],
                  const SizedBox(height: 4),
                  Text(_timeAgo(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 11)),
                ],
              ),
            ),
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(left: AppSpacing.sm, top: 4),
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}
