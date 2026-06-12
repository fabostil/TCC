import 'package:flutter/foundation.dart';

import '../../../core/theme/app_theme_controller.dart';
import '../../../models/comando_personalizado.dart';
import '../../../models/configuracao_app.dart';
import '../../../repositories/comando_personalizado_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/services/custom_command_service.dart';

class SettingsState {
  final bool loading;
  final ConfiguracaoApp? configuration;
  final List<ComandoPersonalizado> customCommands;

  const SettingsState({
    required this.loading,
    required this.configuration,
    required this.customCommands,
  });

  const SettingsState.initial()
    : loading = true,
      configuration = null,
      customCommands = const [];

  SettingsState copyWith({
    bool? loading,
    ConfiguracaoApp? configuration,
    List<ComandoPersonalizado>? customCommands,
  }) {
    return SettingsState(
      loading: loading ?? this.loading,
      configuration: configuration ?? this.configuration,
      customCommands: customCommands ?? this.customCommands,
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController({
    ConfiguracaoAppRepository? configuracaoRepository,
    ComandoPersonalizadoRepository? comandoRepository,
    AppThemeController? themeController,
  }) : _configuracaoRepository =
           configuracaoRepository ?? ConfiguracaoAppRepository.instance,
       _comandoRepository =
           comandoRepository ?? ComandoPersonalizadoRepository.instance,
       _themeController = themeController ?? AppThemeController.instance;

  final ConfiguracaoAppRepository _configuracaoRepository;
  final ComandoPersonalizadoRepository _comandoRepository;
  final AppThemeController _themeController;

  SettingsState _state = const SettingsState.initial();

  SettingsState get state => _state;

  Future<void> load({required int? usuarioId}) async {
    final configuration = await _configuracaoRepository.buscarConfiguracao();
    final customCommands = await _listCustomCommands(usuarioId);
    _setState(
      _state.copyWith(
        loading: false,
        configuration: configuration,
        customCommands: customCommands,
      ),
    );
  }

  Future<ConfiguracaoApp> saveConfiguration(
    ConfiguracaoApp configuration,
  ) async {
    _setState(_state.copyWith(configuration: configuration));
    await _configuracaoRepository.salvarConfiguracao(configuration);
    return configuration;
  }

  Future<ConfiguracaoApp> setDarkTheme(bool active) async {
    final configuration = _requireConfiguration();
    final updated = await saveConfiguration(
      configuration.copyWith(temaEscuro: active),
    );
    await _themeController.definirTemaEscuro(active);
    return updated;
  }

  Future<void> saveCustomCommand({
    required int? usuarioId,
    required String phrase,
    required String commandType,
  }) async {
    final cleanPhrase = phrase.trim();
    final normalizedPhrase = CustomCommandRules.normalizePhrase(cleanPhrase);
    if (usuarioId == null) {
      throw StateError('Entre novamente para criar comandos personalizados.');
    }
    if (normalizedPhrase.isEmpty) {
      throw ArgumentError('Informe uma frase válida para o comando.');
    }
    if (normalizedPhrase.length < CustomCommandRules.minPhraseLength) {
      throw ArgumentError('Informe uma frase com pelo menos 3 caracteres.');
    }
    if (CustomCommandRules.isReservedPhrase(cleanPhrase)) {
      throw ArgumentError(CustomCommandRules.reservedPhraseMessage);
    }

    final action = CustomCommandCatalog.findByTipo(commandType);
    if (action == null) {
      throw ArgumentError('Selecione uma ação válida.');
    }

    final existingCommands = await _comandoRepository.listarPorUsuario(
      usuarioId,
    );
    final duplicate = existingCommands.any(
      (command) =>
          CustomCommandRules.normalizePhrase(command.frase) == normalizedPhrase,
    );
    if (duplicate) {
      throw ArgumentError(
        'Você já cadastrou essa frase. Escolha outra para o comando.',
      );
    }

    await _comandoRepository.salvar(
      ComandoPersonalizado(
        usuarioId: usuarioId,
        frase: cleanPhrase,
        tipoComando: action.tipoComando,
        ativo: true,
        dataCriacao: DateTime.now().toIso8601String(),
      ),
    );
    await reloadCustomCommands(usuarioId: usuarioId);
  }

  Future<void> toggleCustomCommand(
    ComandoPersonalizado command,
    bool active, {
    required int? usuarioId,
  }) async {
    final id = command.id;
    if (id == null) {
      return;
    }

    await _comandoRepository.alternarAtivo(id: id, ativo: active);
    await reloadCustomCommands(usuarioId: usuarioId);
  }

  Future<void> deleteCustomCommand(
    ComandoPersonalizado command, {
    required int? usuarioId,
  }) async {
    final id = command.id;
    if (id == null) {
      return;
    }

    await _comandoRepository.excluir(id);
    await reloadCustomCommands(usuarioId: usuarioId);
  }

  Future<void> reloadCustomCommands({required int? usuarioId}) async {
    final customCommands = await _listCustomCommands(usuarioId);
    _setState(_state.copyWith(customCommands: customCommands));
  }

  ConfiguracaoApp _requireConfiguration() {
    final configuration = _state.configuration;
    if (configuration == null) {
      throw StateError('Configuração ainda não carregada.');
    }
    return configuration;
  }

  Future<List<ComandoPersonalizado>> _listCustomCommands(int? usuarioId) {
    if (usuarioId == null) {
      return Future.value([]);
    }

    return _comandoRepository.listarPorUsuario(usuarioId);
  }

  void _setState(SettingsState nextState) {
    _state = nextState;
    notifyListeners();
  }
}
