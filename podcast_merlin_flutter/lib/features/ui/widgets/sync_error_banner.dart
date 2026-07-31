import 'package:flutter/material.dart';

class SyncErrorBanner extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const SyncErrorBanner({
    super.key,
    required this.errorMessage,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                errorMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (onRetry != null) ...[
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              const SizedBox(width: 4),
            ],
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close, color: colorScheme.onErrorContainer, size: 20),
                tooltip: 'Dismiss error',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
