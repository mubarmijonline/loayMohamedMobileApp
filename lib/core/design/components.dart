import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_spacing.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 72,
    this.color = Colors.white,
    this.accent = AppColors.accentLight,
    this.textStyle,
  });

  final double size;
  final Color color;
  final Color accent;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final labelStyle = textStyle ??
        Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
              height: 1,
            );
    final iconSize = size * 0.86;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child:
                    Icon(Icons.add_rounded, color: accent, size: size * 0.24),
              ),
              Positioned(
                left: size * 0.08,
                top: size * 0.12,
                child: CustomPaint(
                  size: Size(size * 0.52, size * 0.32),
                  painter: _LoaySmilePainter(color: color),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: size * 0.14),
        Text('LOAY', style: labelStyle),
      ],
    );
  }
}

class _LoaySmilePainter extends CustomPainter {
  _LoaySmilePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.14
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.1,
      size.width * 0.84,
      size.height * 0.72,
    );
    canvas.drawArc(rect, 0.14, 2.75, false, paint);
  }

  @override
  bool shouldRepaint(covariant _LoaySmilePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ───────────────────────────── PremiumCard ─────────────────────────────

/// Surface card matching the brief: white, radius 16, soft shadow, 0 margin.
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = scheme.surface;
    // In dark mode shadows are invisible against the dark scaffold, so always
    // draw a subtle outline so cards remain distinguishable. In light mode
    // we keep the soft drop shadow.
    final effectiveBorder = borderColor ??
        (gradient == null && isDark
            ? scheme.outline.withValues(alpha: 0.35)
            : null);
    return Material(
      color: gradient == null ? surface : Colors.transparent,
      borderRadius: radius,
      elevation: 0,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? surface : null,
          gradient: gradient,
          borderRadius: radius,
          border: effectiveBorder == null
              ? null
              : Border.all(color: effectiveBorder, width: 1),
          boxShadow: gradient == null && !isDark
              ? const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ───────────────────────────── KpiCard ─────────────────────────────

/// Vertical KPI tile (icon, value, label). Designed to fit a 3-column row.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            // A light shadow over a dark scaffold reads as a glow, not depth.
            color: context.palette.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
            ),
          if (icon != null) const SizedBox(height: 22),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
              height: 1,
              fontSize: 28,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── StatusBadge ─────────────────────────────

/// Pill badge with status-aware color pairs from the brief.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.color,
    this.icon,
  });

  final String label;
  final Color background;
  final Color color;
  final IconData? icon;

  factory StatusBadge.fromStatus(String status, {IconData? icon}) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'pending':
      case 'due':
        return StatusBadge(
          label: status,
          background: AppColors.pendingBg,
          color: AppColors.pendingText,
          icon: icon,
        );
      case 'approved':
      case 'active':
      case 'submitted':
      case 'completed':
        return StatusBadge(
          label: status,
          background: AppColors.approvedBg,
          color: AppColors.approvedText,
          icon: icon,
        );
      case 'rejected':
      case 'overdue':
        return StatusBadge(
          label: status,
          background: AppColors.rejectedBg,
          color: AppColors.rejectedText,
          icon: icon,
        );
      case 'cancelled':
        return StatusBadge(
          label: status,
          background: AppColors.cancelledBg,
          color: AppColors.cancelledText,
          icon: icon,
        );
      default:
        return StatusBadge(
          label: status,
          background: AppColors.infoLight,
          color: AppColors.info,
          icon: icon,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // In dark mode the caller's pastel would be the brightest thing on the
    // card, so the fill is derived from the badge's own foreground instead.
    // Light mode keeps the exact colour it was given.
    final fill =
        context.palette.isDark ? color.withValues(alpha: 0.18) : background;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label[0].toUpperCase() + label.substring(1),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

// Backwards-compat wrapper used by older screens.
@Deprecated('Use StatusBadge')
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: label,
      background: color.withValues(alpha: 0.12),
      color: color,
    );
  }
}

// ───────────────────────────── ProgressBar ─────────────────────────────

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color});
  final double value; // 0..1
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: 8,
        backgroundColor: context.palette.divider,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? AppColors.accent),
      ),
    );
  }
}

// ───────────────────────────── SkeletonBox ─────────────────────────────

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = 8,
  });
  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.palette.divider,
      highlightColor: context.palette.surfaceAlt,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ───────────────────────────── EmptyState (layered-circles) ─────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _LayeredCircles(icon: icon)
                .animate()
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 400.ms),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!.animate().fadeIn(duration: 400.ms, delay: 450.ms),
            ],
          ],
        ),
      ),
    );
  }
}

class _LayeredCircles extends StatelessWidget {
  const _LayeredCircles({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.palette.surface,
              border: Border.all(color: context.palette.divider),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 36,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── ErrorStateView ─────────────────────────────

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Something went wrong',
      message: message,
      icon: Icons.cloud_off_rounded,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
    );
  }
}

// ───────────────────────────── CenteredScroll ─────────────────────────────

/// Wraps a widget so it sits centered in the viewport while remaining
/// scrollable (so RefreshIndicator works) and growing as needed.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

// ───────────────────────────── SectionHeader ─────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ───────────────────────────── AvatarInitials ─────────────────────────────

class AvatarInitials extends StatelessWidget {
  const AvatarInitials({
    super.key,
    required this.name,
    this.size = 44,
    this.ring = false,
  });
  final String name;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final inner = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.38,
              height: 1,
            ),
      ),
    );
    if (!ring) return inner;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: inner,
    );
  }

  static String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'S';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
