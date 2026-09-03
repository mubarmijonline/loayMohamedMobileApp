import 'package:flutter/material.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/error/failures.dart';

/// Renders an error state with an optional Retry button. When the error is a
/// "permanent" failure (forbidden / not-found) the Retry button is hidden.
class SectionError extends StatelessWidget {
  const SectionError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String message;
    bool canRetry = true;

    if (error is ForbiddenFailure) {
      message = 'You are not linked to this student.';
      canRetry = false;
    } else if (error is NotFoundFailure) {
      message = 'Student not found.';
      canRetry = false;
    } else if (error is AppFailure) {
      message = (error as AppFailure).message;
    } else {
      message = 'Something went wrong.';
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 40, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.sm),
          Text(message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
          if (canRetry) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
