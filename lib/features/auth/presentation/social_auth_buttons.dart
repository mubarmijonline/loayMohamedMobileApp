import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import 'auth_controller.dart';

/// "Continue with Apple / Google" buttons + an "or" divider.
///
/// Drop on top of any auth form. Tapping a button calls the corresponding
/// `AuthController` flow and routes to `/home` on success.
class SocialAuthButtons extends ConsumerWidget {
  const SocialAuthButtons({
    super.key,
    this.onSuccess,
    this.dividerLabel = 'or continue with email',
  });

  final VoidCallback? onSuccess;
  final String dividerLabel;

  Future<void> _go(WidgetRef ref, BuildContext context, Future<bool> task)
      async {
    final ok = await task;
    if (!context.mounted) return;
    if (ok) {
      if (onSuccess != null) {
        onSuccess!();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final loading = state.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (Platform.isIOS || Platform.isMacOS)
          _SocialButton(
            label: 'Continue with Apple',
            icon: Icons.apple,
            background: Colors.black,
            foreground: Colors.white,
            onPressed: loading
                ? null
                : () => _go(ref, context, ctrl.loginWithApple()),
          ),
        if (Platform.isIOS || Platform.isMacOS) const SizedBox(height: 10),
        _SocialButton(
          label: 'Continue with Google',
          iconWidget: const _GoogleGlyph(),
          background: Colors.white,
          foreground: const Color(0xFF1F1F1F),
          border: const BorderSide(color: AppColors.divider),
          onPressed: loading
              ? null
              : () => _go(ref, context, ctrl.loginWithGoogle()),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                dividerLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.divider)),
          ],
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconWidget,
    this.border,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final Widget? iconWidget;
  final BorderSide? border;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Material(
        color: background,
        elevation: 0,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: border != null ? Border.fromBorderSide(border!) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (iconWidget != null)
                  iconWidget!
                else if (icon != null)
                  Icon(icon, size: 22, color: foreground),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();
  @override
  Widget build(BuildContext context) {
    // Simple "G" glyph in Google's brand colors. Avoids shipping an asset.
    return const SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 20,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
