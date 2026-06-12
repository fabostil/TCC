import 'package:app_voz/features/settings/controllers/settings_controller.dart';
import 'package:app_voz/features/voices/services/custom_command_service.dart';
import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:app_voz/repositories/comando_personalizado_repository.dart';
import 'package:app_voz/repositories/configuracao_app_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsController', () {
    late FakeConfiguracaoRepository configuracaoRepository;
    late FakeComandoRepository comandoRepository;
    late SettingsController controller;

    setUp(() {
      configuracaoRepository = FakeConfiguracaoRepository();
      comandoRepository = FakeComandoRepository();
      controller = SettingsController(
        configuracaoRepository: configuracaoRepository,
        comandoRepository: comandoRepository,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('carrega configuracao e comandos personalizados', () async {
      comandoRepository.commands = [_customCommand(id: 1)];

      await controller.load(usuarioId: 7);

      expect(controller.state.loading, isFalse);
      expect(controller.state.configuration, isNotNull);
      expect(controller.state.customCommands, hasLength(1));
      expect(comandoRepository.lastUserId, 7);
    });

    test('salva configuracao atualizando estado', () async {
      await controller.load(usuarioId: 7);
      final updated = controller.state.configuration!.copyWith(
        feedbackSonoro: true,
      );

      await controller.saveConfiguration(updated);

      expect(controller.state.configuration!.feedbackSonoro, isTrue);
      expect(
        configuracaoRepository.savedConfigurations.single.feedbackSonoro,
        isTrue,
      );
    });

    test('salva comando personalizado e recarrega lista', () async {
      await controller.load(usuarioId: 7);

      await controller.saveCustomCommand(
        usuarioId: 7,
        phrase: 'modo palco',
        commandType: CustomCommandCatalog.actions.first.tipoComando,
      );

      expect(comandoRepository.savedCommands.single.frase, 'modo palco');
      expect(controller.state.customCommands, hasLength(1));
    });

    test('rejeita comando personalizado sem usuario', () async {
      await controller.load(usuarioId: null);

      expect(
        () => controller.saveCustomCommand(
          usuarioId: null,
          phrase: 'modo palco',
          commandType: CustomCommandCatalog.actions.first.tipoComando,
        ),
        throwsStateError,
      );
    });

    test('rejeita frase vazia apos normalizacao', () async {
      await controller.load(usuarioId: 7);

      expect(
        () => controller.saveCustomCommand(
          usuarioId: 7,
          phrase: '!!!',
          commandType: CustomCommandCatalog.actions.first.tipoComando,
        ),
        throwsArgumentError,
      );
    });

    test('rejeita frase reservada do app', () async {
      await controller.load(usuarioId: 7);

      expect(
        () => controller.saveCustomCommand(
          usuarioId: 7,
          phrase: 'voltar',
          commandType: CustomCommandCatalog.actions.first.tipoComando,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            CustomCommandRules.reservedPhraseMessage,
          ),
        ),
      );
    });

    test('rejeita frase duplicada por normalizacao', () async {
      comandoRepository.commands = [_customCommand(id: 1)];
      await controller.load(usuarioId: 7);

      expect(
        () => controller.saveCustomCommand(
          usuarioId: 7,
          phrase: '  modo   palco! ',
          commandType: CustomCommandCatalog.actions.last.tipoComando,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Você já cadastrou essa frase. Escolha outra para o comando.',
          ),
        ),
      );
    });
  });
}

ComandoPersonalizado _customCommand({required int id}) {
  return ComandoPersonalizado(
    id: id,
    usuarioId: 7,
    frase: 'modo palco',
    tipoComando: CustomCommandCatalog.actions.first.tipoComando,
    ativo: true,
    dataCriacao: '2026-05-19T10:00:00.000',
  );
}

class FakeConfiguracaoRepository implements ConfiguracaoAppRepository {
  ConfiguracaoApp configuration = ConfiguracaoApp.padrao();
  final savedConfigurations = <ConfiguracaoApp>[];

  @override
  Future<ConfiguracaoApp> buscarConfiguracao() async => configuration;

  @override
  Future<void> salvarConfiguracao(ConfiguracaoApp configuracao) async {
    configuration = configuracao;
    savedConfigurations.add(configuracao);
  }

  @override
  Future<void> atualizarComandosVoz(bool ativo) async {}

  @override
  Future<void> atualizarEscutaContinua(bool ativo) async {}

  @override
  Future<void> atualizarFeedbackSonoro(bool ativo) async {}

  @override
  Future<void> atualizarParadaSilencio(bool ativo) async {}

  @override
  Future<void> atualizarTemaEscuro(bool ativo) async {}

  @override
  Future<void> atualizarTempoSilencio(int segundos) async {}

  @override
  Future<void> concluirPrimeiraExecucao({
    required bool comandosVozAtivos,
  }) async {}
}

class FakeComandoRepository implements ComandoPersonalizadoRepository {
  List<ComandoPersonalizado> commands = [];
  final savedCommands = <ComandoPersonalizado>[];
  int? lastUserId;

  @override
  Future<int> salvar(ComandoPersonalizado comando) async {
    savedCommands.add(comando);
    commands = [comando.copyWith(id: savedCommands.length), ...commands];
    return savedCommands.length;
  }

  @override
  Future<List<ComandoPersonalizado>> listarPorUsuario(int usuarioId) async {
    lastUserId = usuarioId;
    return commands;
  }

  @override
  Future<List<ComandoPersonalizado>> listarAtivosPorUsuario(
    int usuarioId,
  ) async {
    return commands.where((command) => command.ativo).toList();
  }

  @override
  Future<void> alternarAtivo({required int id, required bool ativo}) async {}

  @override
  Future<void> excluir(int id) async {}
}
