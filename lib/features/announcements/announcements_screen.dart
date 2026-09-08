import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../providers.dart';

class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsProvider('global'));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () async =>
            ref.refresh(announcementsProvider('global').future),
        child: list.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: List.generate(
              4,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: SkeletonBox(height: 120, radius: AppRadius.lg),
              ),
            ),
          ),
          error: (e, _) => CenteredScroll(
            child: ErrorStateView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () => ref.invalidate(announcementsProvider('global')),
            ),
          ),
          data: (items) => items.isEmpty
              ? const CenteredScroll(
                  child: EmptyState(
                    title: 'No announcements',
                    message: "You're all caught up.",
                    icon: Icons.campaign_outlined,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final a = items[i];
                    return PremiumCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: AppColors.cyanGradient,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                                child: const Icon(Icons.campaign_rounded,
                                    color: Colors.white),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title,
                                        style: theme.textTheme.titleSmall),
                                    Text(
                                      DateFormat.yMMMd()
                                          .add_jm()
                                          .format(a.publishedAt),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.65)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(a.body),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
