import 'package:app_voz/features/voices/coordination/voice_confirmation_controller.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const commandService = CommandService();

  group('VoiceConfirmationController', () {
    test('sem confirmacao pendente, sim nao executa nada', () async {
      final controller = VoiceConfirmationController();

      final result = await controller.handle(commandService.interpret('sim'));

      expect(result.action, VoiceConfirmationAction.notHandled);
      expect(controller.hasPendingConfirmation, isFalse);
    });

    test('com confirmacao pendente, sim confirma e limpa estado', () async {
      final controller = VoiceConfirmationController();
      var confirmed = 0;

      controller.register(
        VoiceConfirmationRequest(
          id: 'delete',
          description: 'Exclusao',
          onConfirm: () {
            confirmed++;
          },
        ),
      );

      final result = await controller.handle(commandService.interpret('sim'));

      expect(result.action, VoiceConfirmationAction.confirmed);
      expect(confirmed, 1);
      expect(controller.hasPendingConfirmation, isFalse);
    });

    test('confirmar exclusao confirma e limpa estado', () async {
      final controller = VoiceConfirmationController();
      var confirmed = false;

      controller.register(
        VoiceConfirmationRequest(
          id: 'delete',
          description: 'Exclusao',
          onConfirm: () {
            confirmed = true;
          },
        ),
      );

      final result = await controller.handle(
        commandService.interpret('confirmar exclusao'),
      );

      expect(result.action, VoiceConfirmationAction.confirmed);
      expect(confirmed, isTrue);
      expect(controller.hasPendingConfirmation, isFalse);
    });

    test('cancelar e nao cancelam e limpam estado', () async {
      for (final text in ['cancelar', 'nao']) {
        final controller = VoiceConfirmationController();
        var cancelled = 0;

        controller.register(
          VoiceConfirmationRequest(
            id: 'delete',
            description: 'Exclusao',
            onConfirm: () {},
            onCancel: () {
              cancelled++;
            },
          ),
        );

        final result = await controller.handle(commandService.interpret(text));

        expect(result.action, VoiceConfirmationAction.cancelled);
        expect(cancelled, 1);
        expect(controller.hasPendingConfirmation, isFalse);
      }
    });

    test('comando desconhecido nao confirma e mantem pendencia', () async {
      final controller = VoiceConfirmationController();
      var confirmed = false;

      controller.register(
        VoiceConfirmationRequest(
          id: 'delete',
          description: 'Exclusao',
          onConfirm: () {
            confirmed = true;
          },
        ),
      );

      final result = await controller.handle(
        commandService.interpret('abrir afinador'),
      );

      expect(result.action, VoiceConfirmationAction.blocked);
      expect(confirmed, isFalse);
      expect(controller.hasPendingConfirmation, isTrue);
    });

    test('comando global durante confirmacao fica bloqueado', () async {
      final controller = VoiceConfirmationController();

      controller.register(
        VoiceConfirmationRequest(
          id: 'delete',
          description: 'Exclusao',
          onConfirm: () {},
        ),
      );

      final result = await controller.handle(
        commandService.interpret('configuracoes'),
      );

      expect(result.action, VoiceConfirmationAction.blocked);
      expect(controller.hasPendingConfirmation, isTrue);
    });
  });
}
