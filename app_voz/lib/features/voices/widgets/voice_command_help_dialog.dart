import 'package:flutter/material.dart';

class VoiceCommandHelpDialog extends StatelessWidget {
  const VoiceCommandHelpDialog({super.key});

  static const _sections = [
    _VoiceCommandHelpSection(
      title: 'Navegação',
      commands: [
        'Meus projetos',
        'Minhas gravações',
        'Dashboard',
        'Histórico',
        'Configurações',
        'Tela inicial',
        'Voltar',
      ],
    ),
    _VoiceCommandHelpSection(
      title: 'Gravação',
      commands: [
        'Gravar',
        'Pausar gravação',
        'Retomar gravação',
        'Finalizar gravação',
      ],
    ),
    _VoiceCommandHelpSection(
      title: 'Reprodução',
      commands: ['Tocar', 'Dar play', 'Parar reprodução'],
    ),
    _VoiceCommandHelpSection(
      title: 'Listas',
      commands: ['Descer', 'Subir', 'Ir para o topo', 'Ir para o fim'],
    ),
    _VoiceCommandHelpSection(
      title: 'Confirmações',
      commands: ['Confirmar', 'Cancelar', 'Não', 'Sim'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Comandos de voz'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Você pode controlar o app dizendo frases como estas:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final section in _sections) ...[
                _VoiceCommandHelpSectionView(section: section),
                const SizedBox(height: 16),
              ],
              Text(
                'Você também pode criar comandos personalizados em Configurações.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Os comandos também funcionam com variações naturais, como '
                '“abre configurações” ou “vai para projetos”.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('voice_command_help_close_button'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

Future<void> showVoiceCommandHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const VoiceCommandHelpDialog(),
  );
}

class _VoiceCommandHelpSectionView extends StatelessWidget {
  const _VoiceCommandHelpSectionView({required this.section});

  final _VoiceCommandHelpSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final command in section.commands)
              Chip(label: Text(command), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
    );
  }
}

class _VoiceCommandHelpSection {
  final String title;
  final List<String> commands;

  const _VoiceCommandHelpSection({required this.title, required this.commands});
}
