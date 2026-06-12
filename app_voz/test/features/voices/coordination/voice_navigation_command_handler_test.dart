import 'package:app_voz/features/voices/coordination/voice_navigation_command_handler.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const commandService = CommandService();

  group('VoiceNavigationCommandHandler', () {
    test('trata comandos globais de navegacao principais', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.other,
        goHome: _record(calls, 'home'),
        openProjects: _record(calls, 'projects'),
        openRecordings: _record(calls, 'recordings'),
        openDashboard: _record(calls, 'dashboard'),
        openHistory: _record(calls, 'history'),
        openSettings: _record(calls, 'settings'),
        openNewProject: _record(calls, 'new_project'),
        goBack: _record(calls, 'back'),
      );

      await handler.handle(commandService.interpret('dashboard'));
      await handler.handle(commandService.interpret('historico'));
      await handler.handle(commandService.interpret('configuracoes'));
      await handler.handle(commandService.interpret('projetos'));
      await handler.handle(commandService.interpret('gravacoes'));
      await handler.handle(commandService.interpret('novo projeto'));
      await handler.handle(commandService.interpret('tela inicial'));
      await handler.handle(commandService.interpret('voltar'));

      expect(calls, [
        'dashboard',
        'history',
        'settings',
        'projects',
        'recordings',
        'new_project',
        'home',
        'back',
      ]);
    });

    test('nao duplica rota quando destino atual ja esta aberto', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.settings,
        openSettings: _record(calls, 'settings'),
      );

      final result = await handler.handle(
        commandService.interpret('abrir configuracoes'),
      );

      expect(calls, isEmpty);
      expect(result?.statusMessage, 'Configuracoes ja esta aberto.');
    });

    test('permite preservar criar projeto como comando contextual', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.projects,
        openNewProject: _record(calls, 'new_project'),
        handleCreateProjectCommand: false,
      );

      final result = await handler.handle(
        commandService.interpret('criar projeto'),
      );

      expect(result, isNull);
      expect(calls, isEmpty);
    });

    test('retorna null para comando desconhecido', () async {
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.home,
      );

      final result = await handler.handle(
        commandService.interpret('abrir afinador'),
      );

      expect(result, isNull);
    });
  });
}

VoiceNavigationAction _record(List<String> calls, String value) {
  return (_) async {
    calls.add(value);
    return VoiceCommandPageResult.handled(restartListening: false);
  };
}
