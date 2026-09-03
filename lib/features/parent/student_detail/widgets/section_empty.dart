import 'package:flutter/material.dart';

import '../../../../core/design/app_spacing.dart';

class SectionEmpty extends StatelessWidget {
  const SectionEmpty({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: AppSpacing.sm),
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
