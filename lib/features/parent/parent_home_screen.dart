import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/utils/legal_links.dart';
import '../auth/domain/student_user.dart';
import '../auth/presentation/auth_controller.dart';
import 'student_detail/parent_student_detail_screen.dart';
import '../../core/design/app_palette.dart';

/// Parent home — shows all linked students and lets the parent tap into each.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;
    final students = user?.linkedStudents ?? const [];

    return Scaffold(
      backgroundColor: context.palette.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.authBackgroundGradient,
                ),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 60, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      user?.name.isNotEmpty == true
                          ? 'Hello, ${user!.name}'
                          : 'Parent Portal',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: context.palette.onBrand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      students.isEmpty
                          ? 'Parent portal'
                          : '${students.length} student${students.length == 1 ? '' : 's'} linked to your account',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Privacy policy',
                icon: const Icon(
                  Icons.privacy_tip_outlined,
                  color: Colors.white,
                ),
                onPressed: () =>
                    LegalLinks.open(context, LegalLinks.privacyPolicy),
              ),
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                onPressed: () {
                  ref.read(authControllerProvider.notifier).logout();
                  // Navigation to /login is handled centrally in app.dart.
                },
              ),
            ],
          ),

          // ── Content ──────────────────────────────────────────────────
          if (students.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.family_restroom_rounded,
                        size: 72,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.2)),
                    const SizedBox(height: AppSpacing.lg),
                    Text('No students linked yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Ask the school to link your phone number\nto your child\'s account.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _StudentCard(student: students[i]),
                  childCount: students.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formats a raw grade value: "9" → "Grade 9", "Grade 9" → "Grade 9" (idempotent).
String _formatGrade(String raw) {
  final trimmed = raw.trim();
  if (trimmed.toLowerCase().startsWith('grade')) return trimmed;
  return 'Grade $trimmed';
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});
  final LinkedStudent student;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      elevation: 0,
      color: context.palette.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParentStudentDetailScreen(student: student),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 30,
                backgroundColor: context.palette.surfaceTinted,
                backgroundImage: (student.avatarUrl?.isNotEmpty ?? false)
                    ? NetworkImage(student.avatarUrl!)
                    : null,
                child: (student.avatarUrl?.isNotEmpty ?? false)
                    ? null
                    : Text(
                        student.name.isNotEmpty
                            ? student.name[0].toUpperCase()
                            : '?',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (student.grade?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.palette.surfaceTinted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatGrade(student.grade!),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Arrow
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
