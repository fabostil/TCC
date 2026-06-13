import 'package:flutter/material.dart';

enum VoiceCommandHelpContext {
  general,
  home,
  projects,
  recordings,
  editor,
  settings,
}

class VoiceCommandHelpDialog extends StatelessWidget {
  const VoiceCommandHelpDialog({
    super.key,
    this.contextType = VoiceCommandHelpContext.general,
  });

  const VoiceCommandHelpDialog.forHome({super.key})
    : contextType = VoiceCommandHelpContext.home;

  const VoiceCommandHelpDialog.forProjects({super.key})
    : contextType = VoiceCommandHelpContext.projects;

  const VoiceCommandHelpDialog.forRecordings({super.key})
    : contextType = VoiceCommandHelpContext.recordings;

  const VoiceCommandHelpDialog.forEditor({super.key})
    : contextType = VoiceCommandHelpContext.editor;

  const VoiceCommandHelpDialog.forSettings({super.key})
    : contextType = VoiceCommandHelpContext.settings;

  final VoiceCommandHelpContext contextType;

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

  static const _homeSections = [
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
  ];

  static const _projectsSections = [
    _VoiceCommandHelpSection(
      title: 'Projetos',
      commands: [
        'Novo projeto',
        'Criar projeto',
        'Abrir projeto',
        'Excluir projeto',
      ],
    ),
    _VoiceCommandHelpSection(
      title: 'Navegação',
      commands: ['Minhas gravações', 'Configurações', 'Tela inicial'],
    ),
    _VoiceCommandHelpSection(
      title: 'Lista',
      commands: ['Descer', 'Subir', 'Ir para o topo', 'Ir para o fim'],
    ),
  ];

  static const _recordingsSections = [
    _VoiceCommandHelpSection(
      title: 'Reprodução',
      commands: ['Tocar', 'Dar play', 'Parar reprodução'],
    ),
    _VoiceCommandHelpSection(
      title: 'Gravações',
      commands: ['Abrir detalhes', 'Excluir gravação'],
    ),
    _VoiceCommandHelpSection(
      title: 'Lista',
      commands: ['Descer', 'Subir', 'Ir para o topo', 'Ir para o fim'],
    ),
    _VoiceCommandHelpSection(
      title: 'Confirmação',
      commands: ['Confirmar', 'Cancelar'],
    ),
  ];

  static const _editorSections = [
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
      commands: ['Tocar', 'Parar reprodução'],
    ),
    _VoiceCommandHelpSection(
      title: 'Navegação',
      commands: ['Voltar', 'Tela inicial'],
    ),
  ];

  static const _settingsSections = [
    _VoiceCommandHelpSection(
      title: 'Controle por voz',
      commands: ['Ativar controle por voz', 'Desativar controle por voz'],
    ),
    _VoiceCommandHelpSection(
      title: 'Tema',
      commands: ['Modo escuro', 'Tema claro'],
    ),
    _VoiceCommandHelpSection(
      title: 'Comandos personalizados',
      commands: ['Criar comando', 'Excluir comando'],
    ),
    _VoiceCommandHelpSection(
      title: 'Navegação',
      commands: ['Tela inicial', 'Voltar'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _contentFor(contextType);

    return AlertDialog(
      title: Text(content.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(content.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              for (final section in content.sections) ...[
                _VoiceCommandHelpSectionView(section: section),
                const SizedBox(height: 16),
              ],
              if (content.notice != null) ...[
                Text(content.notice!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
              ],
              Text(content.footer, style: theme.textTheme.bodyMedium),
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

  _VoiceCommandHelpContent _contentFor(VoiceCommandHelpContext contextType) {
    return switch (contextType) {
      VoiceCommandHelpContext.home => const _VoiceCommandHelpContent(
        title: 'Comandos de voz',
        description: 'Você pode navegar pelo app dizendo frases como:',
        sections: _homeSections,
        footer:
            'Os comandos também funcionam com variações naturais, como '
            '“abre configurações” ou “vai para projetos”.',
      ),
      VoiceCommandHelpContext.projects => const _VoiceCommandHelpContent(
        title: 'Comandos em projetos',
        description: 'Exemplos de comandos úteis nesta tela:',
        sections: _projectsSections,
        footer: 'Você também pode usar os botões da tela sempre que quiser.',
      ),
      VoiceCommandHelpContext.recordings => const _VoiceCommandHelpContent(
        title: 'Comandos em gravações',
        description: 'Você pode controlar gravações dizendo frases como:',
        sections: _recordingsSections,
        footer: 'Confirmações aparecem antes de ações destrutivas.',
      ),
      VoiceCommandHelpContext.editor => const _VoiceCommandHelpContent(
        title: 'Comandos no editor',
        description: 'Exemplos de comandos para gravar e reproduzir:',
        sections: _editorSections,
        notice:
            'Durante uma gravação, alguns comandos por voz podem ficar '
            'indisponíveis porque o microfone está sendo usado para gravar.',
        footer: 'Use os controles da tela quando a voz estiver pausada.',
      ),
      VoiceCommandHelpContext.settings => const _VoiceCommandHelpContent(
        title: 'Comandos em configurações',
        description: 'Você pode ajustar o app dizendo frases como:',
        sections: _settingsSections,
        footer:
            'Comandos personalizados permitem criar frases próprias em '
            'Configurações.',
      ),
      VoiceCommandHelpContext.general => const _VoiceCommandHelpContent(
        title: 'Comandos de voz',
        description: 'Você pode controlar o app dizendo frases como estas:',
        sections: _sections,
        footer:
            'Você também pode criar comandos personalizados em Configurações. '
            'Os comandos também funcionam com variações naturais, como '
            '“abre configurações” ou “vai para projetos”.',
      ),
    };
  }
}

Future<void> showVoiceCommandHelpDialog(
  BuildContext context, {
  VoiceCommandHelpContext contextType = VoiceCommandHelpContext.general,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => VoiceCommandHelpDialog(contextType: contextType),
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

class _VoiceCommandHelpContent {
  final String title;
  final String description;
  final List<_VoiceCommandHelpSection> sections;
  final String footer;
  final String? notice;

  const _VoiceCommandHelpContent({
    required this.title,
    required this.description,
    required this.sections,
    required this.footer,
    this.notice,
  });
}
