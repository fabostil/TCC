import '../../../models/comando_personalizado.dart';
import '../../../repositories/comando_personalizado_repository.dart';
import 'command_service.dart';

class CustomCommandAction {
  const CustomCommandAction({
    required this.tipoComando,
    required this.label,
    required this.canonicalPhrase,
  });

  final String tipoComando;
  final String label;
  final String canonicalPhrase;
}

class CustomCommandCatalog {
  static const List<CustomCommandAction> actions = [
    CustomCommandAction(
      tipoComando: 'abrir_dashboard',
      label: 'Abrir dashboard',
      canonicalPhrase: 'abrir dashboard',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_projetos',
      label: 'Abrir projetos',
      canonicalPhrase: 'abrir projetos',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_gravacoes',
      label: 'Abrir gravações',
      canonicalPhrase: 'abrir gravacoes',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_historico',
      label: 'Abrir histórico',
      canonicalPhrase: 'abrir historico',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_configuracoes',
      label: 'Abrir configurações',
      canonicalPhrase: 'abrir configuracoes',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_novo_projeto',
      label: 'Novo projeto',
      canonicalPhrase: 'novo projeto',
    ),
    CustomCommandAction(
      tipoComando: 'abrir_editor',
      label: 'Abrir editor',
      canonicalPhrase: 'abrir editor',
    ),
    CustomCommandAction(
      tipoComando: 'iniciar_gravacao',
      label: 'Iniciar gravação',
      canonicalPhrase: 'iniciar gravacao',
    ),
    CustomCommandAction(
      tipoComando: 'encerrar_gravacao',
      label: 'Encerrar gravação',
      canonicalPhrase: 'encerrar gravacao',
    ),
    CustomCommandAction(
      tipoComando: 'ativar_tema_escuro',
      label: 'Ativar tema escuro',
      canonicalPhrase: 'ativar tema escuro',
    ),
    CustomCommandAction(
      tipoComando: 'desativar_tema_escuro',
      label: 'Ativar tema claro',
      canonicalPhrase: 'ativar tema claro',
    ),
  ];

  static CustomCommandAction? findByTipo(String tipoComando) {
    for (final action in actions) {
      if (action.tipoComando == tipoComando) {
        return action;
      }
    }

    return null;
  }
}

class CustomCommandRules {
  const CustomCommandRules._();

  static const int minPhraseLength = 3;
  static const String reservedPhraseMessage =
      'Esse comando já é usado pelo app. Escolha outra frase.';

  static String normalizePhrase(
    String phrase, {
    CommandService commandService = const CommandService(),
  }) {
    return commandService.normalize(phrase);
  }

  static bool isReservedPhrase(
    String phrase, {
    CommandService commandService = const CommandService(),
  }) {
    return commandService.interpret(phrase).recognized;
  }
}

class CustomCommandService {
  CustomCommandService({
    ComandoPersonalizadoRepository? repository,
    CommandService commandService = const CommandService(),
  }) : _repository = repository ?? ComandoPersonalizadoRepository.instance,
       _commandService = commandService;

  final ComandoPersonalizadoRepository _repository;
  final CommandService _commandService;

  Future<CommandResult> interpret({
    required int usuarioId,
    required String originalText,
    required String normalizedText,
  }) async {
    final comandos = await _repository.listarAtivosPorUsuario(usuarioId);

    for (final comando in comandos) {
      final fraseNormalizada = _commandService.normalize(comando.frase);
      if (fraseNormalizada != normalizedText) {
        continue;
      }

      return _mapCustomCommand(
        originalText: originalText,
        normalizedText: normalizedText,
        comando: comando,
      );
    }

    return CommandResult(
      originalText: originalText,
      normalizedText: normalizedText,
      type: VoiceCommandType.desconhecido,
      recognized: false,
      tipoComando: 'desconhecido',
    );
  }

  CommandResult _mapCustomCommand({
    required String originalText,
    required String normalizedText,
    required ComandoPersonalizado comando,
  }) {
    final action = CustomCommandCatalog.findByTipo(comando.tipoComando);
    if (action == null) {
      return CommandResult(
        originalText: originalText,
        normalizedText: normalizedText,
        type: VoiceCommandType.desconhecido,
        recognized: false,
        tipoComando: 'desconhecido',
      );
    }

    final result = _commandService.interpret(action.canonicalPhrase);
    return CommandResult(
      originalText: originalText,
      normalizedText: normalizedText,
      type: result.type,
      recognized: result.recognized,
      tipoComando: action.tipoComando,
      acaoExecutada: '${result.acaoExecutada} (comando personalizado)',
      parametro: result.parametro,
      parametroSecundario: result.parametroSecundario,
    );
  }
}
