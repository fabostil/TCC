import '../services/command_service.dart';
import 'voice_command_dispatcher.dart';

enum VoiceNavigationDestination {
  home,
  projects,
  recordings,
  dashboard,
  history,
  settings,
  editor,
  other,
}

typedef VoiceNavigationAction =
    Future<VoiceCommandPageResult> Function(CommandResult result);

class VoiceNavigationCommandHandler {
  const VoiceNavigationCommandHandler({
    required this.currentDestination,
    this.goHome,
    this.openProjects,
    this.openRecordings,
    this.openDashboard,
    this.openHistory,
    this.openSettings,
    this.openEditor,
    this.openNewProject,
    this.goBack,
    this.handleCreateProjectCommand = true,
  });

  final VoiceNavigationDestination currentDestination;
  final VoiceNavigationAction? goHome;
  final VoiceNavigationAction? openProjects;
  final VoiceNavigationAction? openRecordings;
  final VoiceNavigationAction? openDashboard;
  final VoiceNavigationAction? openHistory;
  final VoiceNavigationAction? openSettings;
  final VoiceNavigationAction? openEditor;
  final VoiceNavigationAction? openNewProject;
  final VoiceNavigationAction? goBack;
  final bool handleCreateProjectCommand;

  bool canHandle(CommandResult result) => _actionFor(result) != null;

  Future<VoiceCommandPageResult?> handle(CommandResult result) async {
    final action = _actionFor(result);
    if (action == null) {
      return null;
    }

    return action(result);
  }

  VoiceNavigationAction? _actionFor(CommandResult result) {
    return switch (result.type) {
      VoiceCommandType.abrirDashboard => _targetAction(
        VoiceNavigationDestination.dashboard,
        openDashboard,
        'Dashboard já está aberto.',
      ),
      VoiceCommandType.abrirProjetos => _targetAction(
        VoiceNavigationDestination.projects,
        openProjects,
        'Tela de projetos já está aberta.',
      ),
      VoiceCommandType.abrirGravacoes ||
      VoiceCommandType.listarGravacoes => _targetAction(
        VoiceNavigationDestination.recordings,
        openRecordings,
        'Tela de gravações já está aberta.',
      ),
      VoiceCommandType.abrirConfiguracoes => _targetAction(
        VoiceNavigationDestination.settings,
        openSettings,
        'Tela de configurações já está aberta.',
      ),
      VoiceCommandType.abrirHistorico => _targetAction(
        VoiceNavigationDestination.history,
        openHistory,
        'Histórico já está aberto.',
      ),
      VoiceCommandType.abrirEditor => _targetAction(
        VoiceNavigationDestination.editor,
        openEditor,
        'Editor ja esta aberto.',
      ),
      VoiceCommandType.abrirNovoProjeto => openNewProject,
      VoiceCommandType.criarProjeto when handleCreateProjectCommand =>
        openNewProject,
      VoiceCommandType.voltar => _homeOrBackAction(result),
      _ => null,
    };
  }

  VoiceNavigationAction? _targetAction(
    VoiceNavigationDestination destination,
    VoiceNavigationAction? action,
    String currentMessage,
  ) {
    if (currentDestination == destination) {
      return (_) async =>
          VoiceCommandPageResult.handled(message: currentMessage);
    }

    return action;
  }

  VoiceNavigationAction? _homeOrBackAction(CommandResult result) {
    if (!isHomeNavigationCommand(result)) {
      return goBack;
    }

    if (currentDestination == VoiceNavigationDestination.home) {
      return (_) async => VoiceCommandPageResult.handled(
        message: 'Tela inicial ja esta aberta.',
      );
    }

    return goHome;
  }

  static bool isHomeNavigationCommand(CommandResult result) {
    final normalized = result.normalizedText;

    return normalized == 'inicio' ||
        normalized == 'home' ||
        normalized == 'tela inicial' ||
        normalized.contains('tela inicial') ||
        normalized.contains('para home') ||
        normalized.contains('ir para home') ||
        normalized.contains('para inicio') ||
        normalized.contains('para o inicio');
  }
}
