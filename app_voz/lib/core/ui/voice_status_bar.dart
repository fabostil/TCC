import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'user_facing_messages.dart';

class VoiceStatusBar extends StatelessWidget {
  final String message;
  final bool listening;
  final bool thinking;

  const VoiceStatusBar({
    super.key,
    required this.message,
    required this.listening,
    this.thinking = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayMessage = UserFacingMessages.voiceStatus(message);
    final color = thinking
        ? colorScheme.secondary
        : listening
        ? colorScheme.primary
        : colorScheme.outline;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                if (thinking)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Icon(
                    listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: color,
                    size: 20,
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    displayMessage,
                    textAlign: TextAlign.left,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
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
