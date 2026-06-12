import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const commandService = CommandService();

  group('VoiceCommandDispatcher', () {
    test(
      'comando desconhecido sugere comandos uteis sem termo tecnico',
      () async {
        final dispatcher = VoiceCommandDispatcher();

        final result = await dispatcher.dispatch(
          commandService.interpret('abrir afinador'),
        );

        expect(result.handled, isTrue);
        expect(result.statusMessage, contains('Não entendi o comando'));
        expect(result.statusMessage, contains('meus projetos'));
        expect(result.statusMessage, contains('minhas gravações'));
        expect(result.statusMessage, contains('configurações'));
        expect(
          result.statusMessage!.toLowerCase(),
          isNot(contains('exception')),
        );
        expect(result.statusMessage!.toLowerCase(), isNot(contains('service')));
      },
    );

    test(
      'comando reconhecido fora da tela explica indisponibilidade',
      () async {
        final dispatcher = VoiceCommandDispatcher();

        final result = await dispatcher.dispatch(
          commandService.interpret('gravar'),
        );

        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Esse comando não está disponível nesta tela.',
        );
      },
    );
  });
}
