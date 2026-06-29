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
        openEditor: _record(calls, 'editor'),
        openNewProject: _record(calls, 'new_project'),
        goBack: _record(calls, 'back'),
      );

      await handler.handle(commandService.interpret('dashboard'));
      await handler.handle(commandService.interpret('historico'));
      await handler.handle(commandService.interpret('configuracoes'));
      await handler.handle(commandService.interpret('projetos'));
      await handler.handle(commandService.interpret('gravacoes'));
      await handler.handle(commandService.interpret('abrir editor'));
      await handler.handle(commandService.interpret('novo projeto'));
      await handler.handle(commandService.interpret('tela inicial'));
      await handler.handle(commandService.interpret('voltar'));

      expect(calls, [
        'dashboard',
        'history',
        'settings',
        'projects',
        'recordings',
        'editor',
        'new_project',
        'home',
        'back',
      ]);
    });

    test('trata aliases naturais de navegacao global', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.other,
        goHome: _record(calls, 'home'),
        openProjects: _record(calls, 'projects'),
        openRecordings: _record(calls, 'recordings'),
        openDashboard: _record(calls, 'dashboard'),
        openSettings: _record(calls, 'settings'),
        goBack: _record(calls, 'back'),
      );

      await handler.handle(
        commandService.interpret('abre configura\u00e7\u00f5es'),
      );
      await handler.handle(commandService.interpret('vai para projetos'));
      await handler.handle(
        commandService.interpret('mostrar grava\u00e7\u00f5es'),
      );
      await handler.handle(commandService.interpret('ver indicadores'));
      await handler.handle(commandService.interpret('meu painel'));
      await handler.handle(commandService.interpret('prefer\u00eancias'));
      await handler.handle(commandService.interpret('home'));
      await handler.handle(commandService.interpret('volta'));

      expect(calls, [
        'settings',
        'projects',
        'recordings',
        'dashboard',
        'dashboard',
        'settings',
        'home',
        'back',
      ]);
    });

    test('distingue voltar simples de comandos diretos para Home', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.other,
        goHome: _record(calls, 'home'),
        goBack: _record(calls, 'back'),
      );

      await handler.handle(commandService.interpret('voltar'));
      await handler.handle(commandService.interpret('voltar uma tela'));
      await handler.handle(commandService.interpret('tela inicial'));
      await handler.handle(commandService.interpret('inicio'));
      await handler.handle(commandService.interpret('home'));
      await handler.handle(
        commandService.interpret('voltar para tela inicial'),
      );
      await handler.handle(commandService.interpret('voltar para o inicio'));
      await handler.handle(commandService.interpret('ir para o inicio'));
      await handler.handle(commandService.interpret('abre tela inicial'));
      await handler.handle(commandService.interpret('abrir tela inicial'));

      expect(calls, [
        'back',
        'back',
        'home',
        'home',
        'home',
        'home',
        'home',
        'home',
        'home',
        'home',
      ]);
    });

    test('em pilha profunda comando Home aciona goHome direto', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.other,
        goHome: (_) async {
          calls.add('pop_until_home');
          return VoiceCommandPageResult.handled(restartListening: false);
        },
        goBack: _record(calls, 'back'),
      );

      await handler.handle(
        commandService.interpret('voltar para tela inicial'),
      );

      expect(calls, ['pop_until_home']);
    });

    test('na Home comando Home nao duplica rota', () async {
      final calls = <String>[];
      final handler = VoiceNavigationCommandHandler(
        currentDestination: VoiceNavigationDestination.home,
        goHome: _record(calls, 'home'),
        goBack: _record(calls, 'back'),
      );

      final result = await handler.handle(
        commandService.interpret('tela inicial'),
      );

      expect(calls, isEmpty);
      expect(result?.statusMessage, 'Tela inicial ja esta aberta.');
      expect(result?.restartListening, isTrue);
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
      expect(result?.statusMessage, 'Tela de configurações já está aberta.');
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
