import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/services/custom_command_service.dart';
import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/repositories/comando_personalizado_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomCommandRules', () {
    test('normaliza acento, pontuacao e espacos duplicados', () {
      expect(
        CustomCommandRules.normalizePhrase('  Abrir   meu som!  '),
        'abrir meu som',
      );
      expect(
        CustomCommandRules.normalizePhrase('Configura\u00e7\u00f5es???'),
        'configuracoes',
      );
    });

    test('identifica frase vazia ou apenas pontuacao', () {
      expect(CustomCommandRules.normalizePhrase(' !!! '), isEmpty);
    });

    test('bloqueia frase reservada do parser local', () {
      expect(CustomCommandRules.isReservedPhrase('voltar'), isTrue);
      expect(CustomCommandRules.isReservedPhrase('tela inicial'), isTrue);
      expect(CustomCommandRules.isReservedPhrase('modo palco'), isFalse);
    });
  });

  group('CustomCommandService', () {
    late FakeComandoRepository repository;
    late CustomCommandService service;

    setUp(() {
      repository = FakeComandoRepository();
      service = CustomCommandService(repository: repository);
    });

    test('reconhece comando ativo por frase exata', () async {
      repository.commands = [
        _command(frase: 'abrir meu estudio', tipoComando: 'abrir_editor'),
      ];

      final result = await service.interpret(
        usuarioId: 7,
        originalText: 'abrir meu estudio',
        normalizedText: 'abrir meu estudio',
      );

      expect(result.recognized, isTrue);
      expect(result.type, VoiceCommandType.abrirEditor);
      expect(result.tipoComando, 'abrir_editor');
      expect(result.acaoExecutada, contains('comando personalizado'));
    });

    test('reconhece comando ativo sem acento e com espacos extras', () async {
      repository.commands = [
        _command(frase: 'Abrir meu est\u00fadio', tipoComando: 'abrir_editor'),
      ];

      final result = await service.interpret(
        usuarioId: 7,
        originalText: '  abrir   meu estudio!  ',
        normalizedText: const CommandService().normalize(
          '  abrir   meu estudio!  ',
        ),
      );

      expect(result.recognized, isTrue);
      expect(result.type, VoiceCommandType.abrirEditor);
      expect(result.tipoComando, 'abrir_editor');
      expect(result.acaoExecutada, contains('comando personalizado'));
    });

    test('ignora comando desativado', () async {
      repository.commands = [
        _command(
          frase: 'abrir meu som',
          tipoComando: 'abrir_editor',
          ativo: false,
        ),
      ];

      final result = await service.interpret(
        usuarioId: 7,
        originalText: 'abrir meu som',
        normalizedText: 'abrir meu som',
      );

      expect(result.recognized, isFalse);
      expect(result.type, VoiceCommandType.desconhecido);
    });

    test('comando removido nao e encontrado', () async {
      repository.commands = [
        _command(frase: 'abrir meu som', tipoComando: 'abrir_editor'),
      ];
      await repository.excluir(1);

      final result = await service.interpret(
        usuarioId: 7,
        originalText: 'abrir meu som',
        normalizedText: 'abrir meu som',
      );

      expect(result.recognized, isFalse);
      expect(result.type, VoiceCommandType.desconhecido);
    });

    test('comando de outro usuario nao e encontrado', () async {
      repository.commands = [
        _command(
          frase: 'abrir meu som',
          tipoComando: 'abrir_editor',
          usuarioId: 8,
        ),
      ];

      final result = await service.interpret(
        usuarioId: 7,
        originalText: 'abrir meu som',
        normalizedText: 'abrir meu som',
      );

      expect(result.recognized, isFalse);
      expect(result.type, VoiceCommandType.desconhecido);
    });

    test('comando com tipo invalido vira desconhecido controlado', () async {
      repository.commands = [
        _command(frase: 'modo palco', tipoComando: 'acao_inexistente'),
      ];

      final result = await service.interpret(
        usuarioId: 7,
        originalText: 'modo palco',
        normalizedText: 'modo palco',
      );

      expect(result.recognized, isFalse);
      expect(result.type, VoiceCommandType.desconhecido);
      expect(result.tipoComando, 'desconhecido');
    });
  });
}

ComandoPersonalizado _command({
  required String frase,
  required String tipoComando,
  bool ativo = true,
  int usuarioId = 7,
}) {
  return ComandoPersonalizado(
    id: 1,
    usuarioId: usuarioId,
    frase: frase,
    tipoComando: tipoComando,
    ativo: ativo,
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
  Future<void> excluir(int id) async {
    commands = commands.where((command) => command.id != id).toList();
  }
}
