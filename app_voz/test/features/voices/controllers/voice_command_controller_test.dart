import 'package:app_voz/features/voices/controllers/voice_command_controller.dart';
import 'package:app_voz/features/voices/services/ai_command_service.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/services/custom_command_service.dart';
import 'package:app_voz/features/voices/services/voice_feedback_service.dart';
import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/repositories/comando_personalizado_repository.dart';
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

    test('placeholder da IA nao aciona Gemini nem estado pensando', () async {
      var aiCalled = false;
      var thinkingShown = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'SUA_CHAVE_AQUI',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret(
        'abrir afinador',
        onAiStarted: () => thinkingShown = true,
      );

      expect(result.commandResult.type, VoiceCommandType.desconhecido);
      expect(result.usedAi, isFalse);
      expect(result.aiConfigured, isFalse);
      expect(aiCalled, isFalse);
      expect(thinkingShown, isFalse);
    });

    test(
      'IA desabilitada no contexto nao chama Gemini com chave valida',
      () async {
        var aiCalled = false;
        var thinkingShown = false;
        final controller = VoiceCommandController(
          aiCommandService: AiCommandService(
            apiKey: 'real-looking-test-key',
            httpPost: (uri, headers, body, timeout) async {
              aiCalled = true;
              return _geminiResponse('{"action":"nav_history"}');
            },
          ),
          feedbackService: const NoopVoiceFeedbackService(),
        );

        final result = await controller.interpret(
          'item 1',
          aiEnabled: false,
          onAiStarted: () => thinkingShown = true,
        );

        expect(result.commandResult.type, VoiceCommandType.desconhecido);
        expect(result.usedAi, isFalse);
        expect(result.aiConfigured, isTrue);
        expect(aiCalled, isFalse);
        expect(thinkingShown, isFalse);
      },
    );

    test('IA desabilitada nao bloqueia comandos essenciais da Home', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'real-looking-test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final cases = {
        'projetos': VoiceCommandType.abrirProjetos,
        'meus projetos': VoiceCommandType.abrirProjetos,
        'abrir meus projetos': VoiceCommandType.abrirProjetos,
        'novo projeto': VoiceCommandType.abrirNovoProjeto,
        'abrir novo projeto': VoiceCommandType.abrirNovoProjeto,
        'configura\u00e7\u00f5es': VoiceCommandType.abrirConfiguracoes,
        'minhas grava\u00e7\u00f5es': VoiceCommandType.abrirGravacoes,
        'abrir editor': VoiceCommandType.abrirEditor,
        'voltar': VoiceCommandType.voltar,
        'tela inicial': VoiceCommandType.voltar,
      };

      for (final entry in cases.entries) {
        final result = await controller.interpret(entry.key, aiEnabled: false);

        expect(
          result.commandResult.type,
          entry.value,
          reason: 'Comando: ${entry.key}',
        );
        expect(result.usedAi, isFalse, reason: 'Comando: ${entry.key}');
        expect(
          result.source,
          VoiceCommandSource.local,
          reason: 'Comando: ${entry.key}',
        );
      }
      expect(aiCalled, isFalse);
    });

    test('comando essencial nao chama Gemini com chave valida', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'real-looking-test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret('abrir novo projeto');

      expect(result.commandResult.type, VoiceCommandType.abrirNovoProjeto);
      expect(result.usedAi, isFalse);
      expect(result.source, VoiceCommandSource.local);
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
        expect(unknownVoiceCommandMessage, isNot(contains('exception')));
        expect(unknownVoiceCommandMessage, contains('Não entendi o comando'));
        expect(unknownVoiceCommandMessage, contains('meus projetos'));
        expect(unknownVoiceCommandMessage, contains('minhas gravações'));
        expect(unknownVoiceCommandMessage, contains('configurações'));
      },
    );
    test('usa comando personalizado sem chave da IA', () async {
      var aiCalled = false;
      final repository = FakeComandoRepository()
        ..commands = [
          _customCommand(frase: 'modo palco', tipoComando: 'abrir_dashboard'),
        ];
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: '',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        customCommandService: CustomCommandService(repository: repository),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret('Modo palco!', usuarioId: 7);

      expect(result.commandResult.recognized, isTrue);
      expect(result.commandResult.type, VoiceCommandType.abrirDashboard);
      expect(result.commandResult.tipoComando, 'abrir_dashboard');
      expect(result.usedAi, isFalse);
      expect(aiCalled, isFalse);
    });

    test('consulta comando personalizado antes da IA configurada', () async {
      var aiCalled = false;
      final repository = FakeComandoRepository()
        ..commands = [
          _customCommand(
            frase: 'abrir meu est\u00fadio',
            tipoComando: 'abrir_editor',
          ),
        ];
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        customCommandService: CustomCommandService(repository: repository),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final result = await controller.interpret(
        '  Abrir   meu estudio! ',
        usuarioId: 7,
      );

      expect(result.commandResult.recognized, isTrue);
      expect(result.commandResult.type, VoiceCommandType.abrirEditor);
      expect(result.commandResult.tipoComando, 'abrir_editor');
      expect(result.usedAi, isFalse);
      expect(aiCalled, isFalse);
    });

    test(
      'sem comando personalizado segue fallback de nao reconhecido',
      () async {
        final controller = VoiceCommandController(
          aiCommandService: AiCommandService(apiKey: ''),
          customCommandService: CustomCommandService(
            repository: FakeComandoRepository(),
          ),
          feedbackService: const NoopVoiceFeedbackService(),
        );

        final result = await controller.interpret(
          'abrir meu est\u00fadio',
          usuarioId: 7,
        );

        expect(result.commandResult.recognized, isFalse);
        expect(result.commandResult.type, VoiceCommandType.desconhecido);
        expect(result.usedAi, isFalse);
      },
    );

    test(
      'comando global tem prioridade sobre personalizado conflitante',
      () async {
        final repository = FakeComandoRepository()
          ..commands = [
            _customCommand(frase: 'voltar', tipoComando: 'abrir_dashboard'),
          ];
        final controller = VoiceCommandController(
          aiCommandService: AiCommandService(apiKey: ''),
          customCommandService: CustomCommandService(repository: repository),
          feedbackService: const NoopVoiceFeedbackService(),
        );

        final result = await controller.interpret('voltar', usuarioId: 7);

        expect(result.commandResult.type, VoiceCommandType.voltar);
        expect(result.commandResult.tipoComando, 'voltar');
        expect(result.usedAi, isFalse);
      },
    );

    test(
      'comando essencial reservado tem prioridade sobre personalizado',
      () async {
        final repository = FakeComandoRepository()
          ..commands = [
            _customCommand(frase: 'editor', tipoComando: 'abrir_dashboard'),
          ];
        final controller = VoiceCommandController(
          aiCommandService: AiCommandService(apiKey: ''),
          customCommandService: CustomCommandService(repository: repository),
          feedbackService: const NoopVoiceFeedbackService(),
        );

        final result = await controller.interpret('editor', usuarioId: 7);

        expect(result.commandResult.type, VoiceCommandType.abrirEditor);
        expect(result.commandResult.tipoComando, 'abrir_editor');
        expect(result.usedAi, isFalse);
      },
    );

    test('H10.2b comandos posicionais de gravacao nao chamam Gemini', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'real-looking-test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final reconhecidos = <String, VoiceCommandType>{
        'primeira gravação': VoiceCommandType.reproduzirGravacao,
        'segunda gravação': VoiceCommandType.reproduzirGravacao,
        'terceira gravação': VoiceCommandType.reproduzirGravacao,
        'tocar item 1': VoiceCommandType.reproduzirGravacao,
        'reproduzir item 1': VoiceCommandType.reproduzirGravacao,
        'ouvir item 1': VoiceCommandType.reproduzirGravacao,
        'abrir detalhes do item 1': VoiceCommandType.abrirDetalhesGravacao,
      };

      for (final entry in reconhecidos.entries) {
        final result = await controller.interpret(entry.key);
        expect(
          result.commandResult.type,
          entry.value,
          reason: 'Comando: ${entry.key}',
        );
        expect(result.usedAi, isFalse, reason: 'Comando: ${entry.key}');
        expect(
          result.source,
          VoiceCommandSource.local,
          reason: 'Comando: ${entry.key}',
        );
      }

      // "item 1" retorna desconhecido mas nao chama Gemini quando aiEnabled=false
      final itemResult = await controller.interpret('item 1', aiEnabled: false);
      expect(itemResult.commandResult.type, VoiceCommandType.desconhecido);
      expect(itemResult.usedAi, isFalse);

      expect(aiCalled, isFalse);
    });

    test('H10.2 novos aliases essenciais nao chamam Gemini', () async {
      var aiCalled = false;
      final controller = VoiceCommandController(
        aiCommandService: AiCommandService(
          apiKey: 'real-looking-test-key',
          httpPost: (uri, headers, body, timeout) async {
            aiCalled = true;
            return _geminiResponse('{"action":"nav_history"}');
          },
        ),
        feedbackService: const NoopVoiceFeedbackService(),
      );

      final cases = <String, VoiceCommandType>{
        'opções': VoiceCommandType.abrirConfiguracoes,
        'entrar em configurações': VoiceCommandType.abrirConfiguracoes,
        'lista de projetos': VoiceCommandType.abrirProjetos,
        'cadastrar projeto': VoiceCommandType.abrirNovoProjeto,
        'abrir painel': VoiceCommandType.abrirDashboard,
        'ações recentes': VoiceCommandType.abrirHistorico,
        'áudios': VoiceCommandType.abrirGravacoes,
        'entrar no editor': VoiceCommandType.abrirEditor,
        'área de gravação': VoiceCommandType.abrirEditor,
        'confirmar ação': VoiceCommandType.confirmarAcao,
        'pode cancelar': VoiceCommandType.cancelarAcao,
      };

      for (final entry in cases.entries) {
        final result = await controller.interpret(entry.key);
        expect(
          result.commandResult.type,
          entry.value,
          reason: 'Comando: ${entry.key}',
        );
        expect(result.usedAi, isFalse, reason: 'Comando: ${entry.key}');
        expect(
          result.source,
          VoiceCommandSource.local,
          reason: 'Comando: ${entry.key}',
        );
      }
      expect(aiCalled, isFalse);
    });
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

ComandoPersonalizado _customCommand({
  required String frase,
  required String tipoComando,
}) {
  return ComandoPersonalizado(
    id: 1,
    usuarioId: 7,
    frase: frase,
    tipoComando: tipoComando,
    ativo: true,
    dataCriacao: '2026-06-12T10:00:00.000',
  );
}

class FakeComandoRepository implements ComandoPersonalizadoRepository {
  List<ComandoPersonalizado> commands = [];

  @override
  Future<int> salvar(ComandoPersonalizado comando) async => 1;

  @override
  Future<List<ComandoPersonalizado>> listarPorUsuario(int usuarioId) async {
    return commands.where((command) => command.usuarioId == usuarioId).toList();
  }

  @override
  Future<List<ComandoPersonalizado>> listarAtivosPorUsuario(
    int usuarioId,
  ) async {
    return commands
        .where((command) => command.usuarioId == usuarioId && command.ativo)
        .toList();
  }

  @override
  Future<void> alternarAtivo({required int id, required bool ativo}) async {}

  @override
  Future<void> excluir(int id) async {}
}
