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

  group('H10.2b segurança contextual de comandos posicionais', () {
    test(
      'primeira gravacao fora de contexto mostra mensagem segura sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('primeira gravação'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Abra Minhas Gravações para escolher um item.',
        );
      },
    );

    test(
      'segunda gravacao fora de contexto mostra mensagem segura sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('segunda gravação'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Abra Minhas Gravações para escolher um item.',
        );
      },
    );

    test(
      'tocar item 1 fora de contexto mostra mensagem segura sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('tocar item 1'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Abra Minhas Gravações para escolher um item.',
        );
      },
    );

    test(
      'reproduzir item 1 fora de contexto mostra mensagem segura sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('reproduzir item 1'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Abra Minhas Gravações para escolher um item.',
        );
      },
    );

    test(
      'ouvir item 1 fora de contexto mostra mensagem segura sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('ouvir item 1'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Abra Minhas Gravações para escolher um item.',
        );
      },
    );

    test(
      'item 1 fora de contexto retorna nao reconhecido sem playback',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('item 1'),
        );
        expect(result.handled, isTrue);
        expect(result.statusMessage, contains('Não entendi o comando'));
      },
    );

    test(
      'abrir detalhes do item 1 fora de contexto retorna indisponivel',
      () async {
        final dispatcher = VoiceCommandDispatcher();
        final result = await dispatcher.dispatch(
          commandService.interpret('abrir detalhes do item 1'),
        );
        expect(result.handled, isTrue);
        expect(
          result.statusMessage,
          'Esse comando não está disponível nesta tela.',
        );
      },
    );

    test(
      'primeira gravacao com handler registrado chama handler sem mensagem segura',
      () async {
        var handlerCalled = false;
        final dispatcher = VoiceCommandDispatcher(
          handlers: {
            VoiceCommandType.reproduzirGravacao: (result) async {
              handlerCalled = true;
              return VoiceCommandPageResult.handled(
                message: 'Tocando ${result.parametro}.',
              );
            },
          },
        );
        final result = await dispatcher.dispatch(
          commandService.interpret('primeira gravação'),
        );
        expect(handlerCalled, isTrue);
        expect(result.statusMessage, 'Tocando primeira.');
      },
    );
  });
}
