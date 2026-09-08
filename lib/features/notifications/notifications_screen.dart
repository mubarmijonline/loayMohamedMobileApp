import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../_shared/models.dart';
import 'notifications_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _icon(String? cat) {
    switch (cat) {
      case 'announcement':
        return Icons.campaign_rounded;
      case 'assignment_due':
        return Icons.assignment_outlined;
      case 'quiz_due':
        return Icons.quiz_outlined;
      case 'grade_posted':
        return Icons.workspace_premium_outlined;
      case 'enrollment_update':
        return Icons.how_to_reg_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _color(String? cat) {
    switch (cat) {
      case 'announcement':
        return AppColors.secondary;
      case 'assignment_due':
      case 'quiz_due':
        return AppColors.warning;
      case 'grade_posted':
        return AppColors.success;
      case 'enrollment_update':
        return AppColors.secondary;
      default:
        return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    final ctrl = ref.read(notificationsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.items.any((n) => !n.read))
            TextButton(
                onPressed: ctrl.markAllRead, child: const Text('Mark all')),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: ctrl.load,
        child: state.loading && state.items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: List.generate(
                  6,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SkeletonBox(height: 72, radius: AppRadius.lg),
                  ),
                ),
              )
            : state.items.isEmpty
                ? const CenteredScroll(
                    child: EmptyState(
                      title: 'No notifications',
                      message: "You'll see updates here.",
                      icon: Icons.notifications_none_rounded,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) {
                      final n = state.items[i];
                      return _NotificationCell(
                        item: n,
                        icon: _icon(n.category),
                        color: _color(n.category),
                        onTap: () {
                          ctrl.markRead(n.id);
                          if (n.deepLink != null &&
                              n.deepLink!.startsWith('/')) {
                            Navigator.of(context).pushNamed(n.deepLink!);
                          }
                        },
                        theme: theme,
                      );
                    },
                  ),
      ),
    );
  }
}

class _NotificationCell extends StatelessWidget {
  const _NotificationCell({
    required this.item,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.theme,
  });

  final NotificationItem item;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              item.read ? FontWeight.w500 : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!item.read)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.secondary, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65))),
                const SizedBox(height: 4),
                Text(
                  DateFormat.yMMMd().add_jm().format(item.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
