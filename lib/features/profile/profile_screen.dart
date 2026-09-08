import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/env/app_env.dart';
import '../../core/error/failures.dart';
import '../../core/utils/countries.dart';
import '../../core/utils/country_phone_field.dart';
import '../auth/presentation/auth_controller.dart';
import '../../core/design/app_palette.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final file = File(path);
    final bytes = await file.length();
    if (bytes > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image must be 5 MB or less.')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      // Evict any cached version of the previous avatar so the freshly
      // uploaded image is re-fetched from the server (the server may reuse
      // the same URL after overwriting the file).
      final previous = ref.read(authControllerProvider).user?.avatarUrl;
      final resolvedPrev = AppEnv.I.resolveMediaUrl(previous);
      if (resolvedPrev != null && resolvedPrev.isNotEmpty) {
        await NetworkImage(resolvedPrev).evict();
      }
      await ref.read(authRepositoryProvider).uploadProfileImage(path);
      await ref.read(authControllerProvider.notifier).refreshMe();
      // Also evict the new URL in case it matches the old one.
      final next = ref.read(authControllerProvider).user?.avatarUrl;
      final resolvedNext = AppEnv.I.resolveMediaUrl(next);
      if (resolvedNext != null && resolvedNext.isNotEmpty) {
        await NetworkImage(resolvedNext).evict();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AppFailure ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final initials = (user?.name.trim().isNotEmpty == true)
        ? user!.name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0])
            .join()
            .toUpperCase()
        : 'S';

    return Scaffold(
      // Defer to theme.scaffoldBackgroundColor so dark mode is honoured.
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            expandedHeight: 280,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            title: const Text('Profile'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(
                user: user,
                initials: initials,
                uploading: _uploading,
                onPickAvatar: _pickAndUploadAvatar,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((user?.school ?? '').isNotEmpty || user?.grade != null)
                    _InfoStrip(user: user),
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionLabel('Account'),
                  const SizedBox(height: AppSpacing.sm),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _MenuTile(
                          icon: Icons.person_outline_rounded,
                          color: AppColors.primary,
                          title: 'Edit profile',
                          subtitle: 'Name, school, grade & photo',
                          onTap: () => Navigator.of(context)
                              .pushNamed('/complete-profile'),
                        ),
                        const _ThinDivider(),
                        _MenuTile(
                          icon: Icons.phone_iphone_rounded,
                          color: AppColors.info,
                          title: 'Change mobile number',
                          subtitle: user?.phone ?? 'Not set',
                          onTap: () => _editPhone(context, ref, user?.phone),
                        ),
                        const _ThinDivider(),
                        _MenuTile(
                          icon: Icons.lock_outline_rounded,
                          color: AppColors.warning,
                          title: 'Change password',
                          subtitle: 'Update your sign-in password',
                          onTap: () => _changePassword(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionLabel('Preferences'),
                  const SizedBox(height: AppSpacing.sm),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _MenuTile(
                          icon: Icons.tune_rounded,
                          color: AppColors.accent,
                          title: 'App settings',
                          subtitle: 'Notifications, language & more',
                          onTap: () =>
                              Navigator.of(context).pushNamed('/settings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: _MenuTile(
                      icon: Icons.logout_rounded,
                      color: AppColors.danger,
                      title: 'Sign out',
                      subtitle: 'You can sign back in any time',
                      destructive: true,
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Sign out?'),
                            content: const Text(
                              'You will need to sign in again to continue.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(_, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                ),
                                onPressed: () => Navigator.pop(_, true),
                                child: const Text('Sign out'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref
                              .read(authControllerProvider.notifier)
                              .logout();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      'Loay Mohamed E-Learning',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPhone(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final controller = TextEditingController();
    Country country = kDefaultCountry;
    // Try to seed from existing E.164 phone.
    final cur = current ?? '';
    if (cur.startsWith('+')) {
      final found = kCountries.firstWhere(
        (c) => cur.startsWith(c.code),
        orElse: () => kDefaultCountry,
      );
      country = found;
      controller.text = cur.substring(found.code.length);
    } else if (cur.isNotEmpty) {
      controller.text = normalizePhoneDigits(cur);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setLocal) => AlertDialog(
            title: const Text('Change mobile number'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountryPhoneField(
                  country: country,
                  controller: controller,
                  onCountryChanged: (c) => setLocal(() => country = c),
                  label: 'Mobile number',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result != true) return;
    final e164 = toE164(country.code, controller.text);
    if (e164.length < 6) return;
    try {
      await ref.read(authRepositoryProvider).changePhone(e164);
      await ref.read(authControllerProvider.notifier).refreshMe();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile number updated')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AppFailure ? e.message : e.toString())),
      );
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNext = true;
    bool obscureConfirm = true;
    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final theme = Theme.of(sheetCtx);
            return Padding(
              // Lift content above the keyboard.
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: context.palette.divider,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Change password',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Pick a strong new password.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: current,
                        obscureText: obscureCurrent,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          prefixIcon: const Icon(Icons.lock_clock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureCurrent
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setSheet(
                              () => obscureCurrent = !obscureCurrent,
                            ),
                          ),
                        ),
                        validator: (v) => (v ?? '').isEmpty
                            ? 'Enter your current password'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: next,
                        obscureText: obscureNext,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNext
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setSheet(() => obscureNext = !obscureNext),
                          ),
                        ),
                        validator: (v) => (v ?? '').length < 8
                            ? 'Password must be at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: confirm,
                        obscureText: obscureConfirm,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setSheet(
                              () => obscureConfirm = !obscureConfirm,
                            ),
                          ),
                        ),
                        validator: (v) =>
                            v != next.text ? 'Passwords do not match' : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(sheetCtx).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (!(formKey.currentState?.validate() ??
                                          false)) {
                                        return;
                                      }
                                      setSheet(() => busy = true);
                                      try {
                                        await ref
                                            .read(authRepositoryProvider)
                                            .changePassword(
                                              currentPassword: current.text,
                                              newPassword: next.text,
                                            );
                                        if (!sheetCtx.mounted) return;
                                        Navigator.of(sheetCtx).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Password changed successfully',
                                            ),
                                          ),
                                        );
                                      } catch (e) {
                                        if (!sheetCtx.mounted) return;
                                        setSheet(() => busy = false);
                                        ScaffoldMessenger.of(sheetCtx)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              e is AppFailure
                                                  ? e.message
                                                  : e.toString(),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                    ),
                              label: Text(busy ? 'Saving…' : 'Update password'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    current.dispose();
    next.dispose();
    confirm.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.initials,
    required this.uploading,
    required this.onPickAvatar,
  });

  final dynamic user;
  final String initials;
  final bool uploading;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    // Resolve relative paths (e.g. "/uploads/avatars/x.jpg") to an absolute
    // URL the platform image loader can fetch.
    final rawAvatar = (user?.avatarUrl ?? '') as String;
    final avatarUrl = AppEnv.I.resolveMediaUrl(rawAvatar) ?? '';
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            56,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      backgroundImage:
                          avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 28,
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: uploading ? null : onPickAvatar,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: uploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                user?.name ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? '-',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    if (user?.grade != null) {
      tiles.add(
        _InfoTile(
          icon: Icons.school_rounded,
          label: 'Grade',
          value: '${user!.grade}',
        ),
      );
    }
    if ((user?.school ?? '').isNotEmpty) {
      tiles.add(
        _InfoTile(
          icon: Icons.business_rounded,
          label: 'School',
          value: user!.school!,
        ),
      );
    }
    if ((user?.parentPhone ?? '').isNotEmpty) {
      tiles.add(
        _InfoTile(
          icon: Icons.family_restroom_rounded,
          label: 'Parent',
          value: user!.parentPhone!,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.destructive = false,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: destructive
                          ? AppColors.danger
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Divider(height: 1, color: context.palette.divider),
      );
}
