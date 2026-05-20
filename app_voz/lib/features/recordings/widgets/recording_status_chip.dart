import 'package:flutter/material.dart';

import '../../../models/gravacao.dart';

class RecordingStatusChip extends StatelessWidget {
  const RecordingStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = _metadata(colorScheme);

    return Chip(
      avatar: Icon(metadata.icon, size: compact ? 14 : 16),
      label: Text(metadata.label),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: metadata.foreground,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: metadata.background,
      side: BorderSide(color: metadata.border),
    );
  }

  _StatusChipMetadata _metadata(ColorScheme colorScheme) {
    switch (status) {
      case GravacaoStatus.concluida:
        return _StatusChipMetadata(
          label: 'Concluida',
          icon: Icons.check_circle_outline,
          background: colorScheme.primaryContainer,
          foreground: colorScheme.onPrimaryContainer,
          border: colorScheme.primary.withValues(alpha: 0.35),
        );
      case GravacaoStatus.interrompida:
        return _StatusChipMetadata(
          label: 'Interrompida',
          icon: Icons.pause_circle_outline,
          background: colorScheme.tertiaryContainer,
          foreground: colorScheme.onTertiaryContainer,
          border: colorScheme.tertiary.withValues(alpha: 0.35),
        );
      case GravacaoStatus.arquivoAusente:
        return _StatusChipMetadata(
          label: 'Arquivo ausente',
          icon: Icons.error_outline,
          background: colorScheme.errorContainer,
          foreground: colorScheme.onErrorContainer,
          border: colorScheme.error.withValues(alpha: 0.35),
        );
      case GravacaoStatus.excluida:
        return _StatusChipMetadata(
          label: 'Excluida',
          icon: Icons.delete_outline,
          background: colorScheme.surfaceContainerHighest,
          foreground: colorScheme.onSurfaceVariant,
          border: colorScheme.outlineVariant,
        );
      default:
        return _StatusChipMetadata(
          label: 'Indefinida',
          icon: Icons.help_outline,
          background: colorScheme.surfaceContainerHighest,
          foreground: colorScheme.onSurfaceVariant,
          border: colorScheme.outlineVariant,
        );
    }
  }
}

class _StatusChipMetadata {
  const _StatusChipMetadata({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color border;
}
