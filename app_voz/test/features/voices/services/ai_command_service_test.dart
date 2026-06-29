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

    test('trata placeholders de chave como nao configurados', () async {
      for (final placeholder in const [
        'SUA_CHAVE_AQUI',
        'YOUR_KEY_HERE',
        'COLE_SUA_CHAVE_AQUI',
      ]) {
        var called = false;
        final service = AiCommandService(
          apiKey: placeholder,
          httpPost: (uri, headers, body, timeout) async {
            called = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        );

        final result = await service.interpretUnknown('abre algo');

        expect(service.isConfigured, isFalse);
        expect(called, isFalse);
        expect(result.type, VoiceCommandType.desconhecido);
      }
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

    test('mapeia parametros retornados pela Gemini', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse(
            '{"action":"project_name_set","parametro":"abacate"}',
          );
        },
      );

      final result = await service.interpretUnknown(
        'eu quero que voce coloque o nome abacate',
      );

      expect(result.type, VoiceCommandType.definirNomeProjeto);
      expect(result.parametro, 'abacate');
    });

    test('mapeia buscas retornadas pela Gemini', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse(
            '{"action":"recording_search","parametro":"refrao"}',
          );
        },
      );

      final result = await service.interpretUnknown(
        'procura minhas ideias de refrao',
      );

      expect(result.type, VoiceCommandType.buscarGravacoes);
      expect(result.parametro, 'refrao');
      expect(result.tipoComando, 'buscar_gravacoes');
    });

    test('mapeia limpar busca retornado pela Gemini', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse('{"action":"search_clear"}');
        },
      );

      final result = await service.interpretUnknown('mostra tudo de novo');

      expect(result.type, VoiceCommandType.limparBusca);
      expect(result.tipoComando, 'limpar_busca');
    });

    test('mapeia comando de tema escuro retornado pela Gemini', () async {
      final service = AiCommandService(
        apiKey: 'test-key',
        httpPost: (uri, headers, body, timeout) async {
          return _geminiResponse('{"action":"settings_dark_theme_on"}');
        },
      );

      final result = await service.interpretUnknown('prefiro modo escuro');

      expect(result.type, VoiceCommandType.ativarTemaEscuro);
      expect(result.tipoComando, 'ativar_tema_escuro');
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
