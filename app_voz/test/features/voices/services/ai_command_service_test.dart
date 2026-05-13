import 'package:app_voz/features/voices/services/ai_command_service.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiCommandService', () {
    test('retorna desconhecido quando nao ha chave configurada', () async {
      var called = false;
      final service = AiCommandService(
        apiKey: '',
        httpPost: (uri, headers, body, timeout) async {
          called = true;
          return _geminiResponse('{"action":"nav_history"}');
        },
      );

      final result = await service.interpretUnknown(
        'mostra minha linha do tempo',
      );

      expect(called, isFalse);
      expect(result.type, VoiceCommandType.desconhecido);
      expect(result.recognized, isFalse);
    });

    test('mapeia JSON da Gemini para CommandResult reconhecido', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse('{"action":"nav_history"}');
        },
      );

      final result = await service.interpretUnknown(
        'mostra minha linha do tempo',
      );

      expect(result.type, VoiceCommandType.abrirHistorico);
      expect(result.recognized, isTrue);
      expect(result.tipoComando, 'abrir_historico');
    });

    test('aceita JSON envolvido em markdown fence', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse('```json\n{"action":"nav_dashboard"}\n```');
        },
      );

      final result = await service.interpretUnknown('quero ver meus numeros');

      expect(result.type, VoiceCommandType.abrirDashboard);
      expect(result.recognized, isTrue);
    });

    test('respeita limite de requisicoes por minuto', () async {
      var calls = 0;
      final service = AiCommandService(
        apiKey: 'test-key',
        maxRequestsPerMinute: 1,
        httpPost: (uri, headers, body, timeout) async {
          calls++;
          return _geminiResponse('{"action":"nav_settings"}');
        },
      );

      final first = await service.interpretUnknown('ajustes do app');
      final second = await service.interpretUnknown('preferencias');

      expect(first.type, VoiceCommandType.abrirConfiguracoes);
      expect(second.type, VoiceCommandType.desconhecido);
      expect(calls, 1);
    });

    test(
      'retorna desconhecido para JSON invalido ou action desconhecida',
      () async {
        final service = AiCommandService(
          apiKey: 'test-key',
          httpPost: (uri, headers, body, timeout) async {
            return _geminiResponse('{"action":"open_piano_roll"}');
          },
        );

        final result = await service.interpretUnknown('abre o piano roll');

        expect(result.type, VoiceCommandType.desconhecido);
        expect(result.recognized, isFalse);
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
