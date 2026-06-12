import '../services/command_service.dart';
import 'voice_command_dispatcher.dart';

enum VoiceNavigationDestination {
  home,
  projects,
  recordings,
  dashboard,
  history,
  settings,
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
        'Dashboard ja esta aberto.',
      ),
      VoiceCommandType.abrirProjetos => _targetAction(
        VoiceNavigationDestination.projects,
        openProjects,
        'Projetos ja esta aberto.',
      ),
      VoiceCommandType.abrirGravacoes ||
      VoiceCommandType.listarGravacoes => _targetAction(
        VoiceNavigationDestination.recordings,
        openRecordings,
        'Gravacoes ja esta aberto.',
      ),
      VoiceCommandType.abrirConfiguracoes => _targetAction(
        VoiceNavigationDestination.settings,
        openSettings,
        'Configuracoes ja esta aberto.',
      ),
      VoiceCommandType.abrirHistorico => _targetAction(
        VoiceNavigationDestination.history,
        openHistory,
        'Historico ja esta aberto.',
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
    final normalized = result.normalizedText;
    final wantsHome =
        normalized == 'inicio' ||
        normalized == 'tela inicial' ||
        normalized.contains('tela inicial') ||
        normalized.contains('para home') ||
        normalized.contains('ir para home');

    if (!wantsHome) {
      return goBack;
    }

    if (currentDestination == VoiceNavigationDestination.home) {
      return (_) async => VoiceCommandPageResult.handled(
        message: 'Tela inicial ja esta aberta.',
      );
    }

    return goHome;
  }
}
