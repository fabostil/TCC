import 'package:app_voz/features/voices/controllers/voice_command_controller.dart';
import 'package:app_voz/features/voices/services/ai_command_service.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/services/voice_feedback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCommandController', () {
    test('usa CommandService local antes da IA', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret('abrir dashboard');

      expect(result.commandResult.type, VoiceCommandType.abrirDashboard);
      expect(result.usedAi, isFalse);
      expect(aiCalled, isFalse);
    });

    test('aciona IA quando comando local e desconhecido', () async {
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'test-key',
          httpPost: (uri, headers, body, timeout) async {
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret('abre meu resumo criativo');

      expect(result.commandResult.type, VoiceCommandType.abrirHistorico);
      expect(result.usedAi, isTrue);
      expect(result.aiConfigured, isTrue);
    });

    test('nao aciona IA quando chave nao esta configurada', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: '',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret('abrir afinador');

      expect(result.commandResult.type, VoiceCommandType.desconhecido);
      expect(result.usedAi, isFalse);
      expect(result.aiConfigured, isFalse);
      expect(aiCalled, isFalse);
    });

    test('resolve comandos essenciais localmente sem chave da IA', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: '',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final dashboard = await controller.interpret('Dashboard');
      final historico = await controller.interpret('Hist\u00f3rico');
      final configuracoes = await controller.interpret(
        'Configura\u00e7\u00f5es',
      );

      expect(dashboard.commandResult.type, VoiceCommandType.abrirDashboard);
      expect(historico.commandResult.type, VoiceCommandType.abrirHistorico);
      expect(
        configuracoes.commandResult.type,
        VoiceCommandType.abrirConfiguracoes,
      );
      expect(dashboard.usedAi, isFalse);
      expect(historico.usedAi, isFalse);
      expect(configuracoes.usedAi, isFalse);
      expect(aiCalled, isFalse);
    });

    test(
      'comando desconhecido sem IA mantem mensagem amigavel disponivel',
      () async {
        final controller = VoiceCommandController(
          aiCommandService: AiCommandService(apiKey: ''),
          feedbackService: const NoopVoiceFeedbackService(),
        );

        final result = await controller.interpret('abrir afinador');

        expect(result.commandResult.type, VoiceCommandType.desconhecido);
        expect(result.commandResult.recognized, isFalse);
        expect(unknownVoiceCommandMessage, isNot(contains('GEMINI_API_KEY')));
        expect(unknownVoiceCommandMessage, contains('Não entendi o comando'));
      },
    );
  });
}

Map<String, dynamic> _geminiResponse(String text) {
  return {
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  };
}
