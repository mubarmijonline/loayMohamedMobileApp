import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_colors.dart';
import '../core/design/app_spacing.dart';
import '../features/assignments/assignments_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/notifications/notifications_controller.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/subjects/subjects_screen.dart';
import '../core/design/app_palette.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _pages = <Widget>[
    DashboardScreen(),
    SubjectsScreen(),
    AssignmentsScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  void _onTap(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsControllerProvider).unreadCount;
    return Scaffold(
      // Defer to theme.scaffoldBackgroundColor so dark mode is honoured.
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _AppBottomBar(
        index: _index,
        unread: unread,
        onTap: _onTap,
      ),
    );
  }
}

// ───────────────────────── bottom bar ─────────────────────────

class _AppBottomBar extends StatelessWidget {
  const _AppBottomBar({
    required this.index,
    required this.unread,
    required this.onTap,
  });
  final int index;
  final int unread;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        bottomInset > 0 ? bottomInset : AppSpacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: context.palette.shadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: index == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              icon: Icons.menu_book_rounded,
              label: 'Subjects',
              selected: index == 1,
              onTap: () => onTap(1),
            ),
            _NavItem(
              icon: Icons.bolt_rounded,
              label: 'Tasks',
              selected: index == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              icon: Icons.notifications_none_rounded,
              label: 'Inbox',
              selected: index == 3,
              badge: unread,
              onTap: () => onTap(3),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              selected: index == 4,
              onTap: () => onTap(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    // The selected pill is `surfaceTinted`, which is navy in dark mode — so a
    // navy foreground rendered navy-on-navy and the active tab's label was
    // unreadable. Cyan carries on both, and is the brand accent either way.
    final activeColor =
        context.palette.isDark ? AppColors.accent : AppColors.primary;
    final color = selected
        ? activeColor
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 10,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color:
                selected ? context.palette.surfaceTinted : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (badge > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: context.palette.surface,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
