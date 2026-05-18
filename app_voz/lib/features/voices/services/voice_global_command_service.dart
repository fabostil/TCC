import '../../../core/theme/app_theme_controller.dart';
import '../../../models/configuracao_app.dart';
import '../../../repositories/configuracao_app_repository.dart';
import 'command_service.dart';
import 'voice_permission_service.dart';

class VoiceGlobalCommandResult {
  const VoiceGlobalCommandResult({
    required this.handled,
    this.message,
    this.shouldStopListening = false,
    this.updatedConfig,
  });

  const VoiceGlobalCommandResult.notHandled()
    : handled = false,
      message = null,
      shouldStopListening = false,
      updatedConfig = null;

  final bool handled;
  final String? message;
  final bool shouldStopListening;
  final ConfiguracaoApp? updatedConfig;
}

class VoiceGlobalCommandService {
  VoiceGlobalCommandService({
    ConfiguracaoAppRepository? configuracaoRepository,
    VoicePermissionService? permissionService,
    AppThemeController? themeController,
  }) : _configuracaoRepository =
           configuracaoRepository ?? ConfiguracaoAppRepository.instance,
       _permissionService = permissionService ?? const VoicePermissionService(),
       _themeController = themeController ?? AppThemeController.instance;

  final ConfiguracaoAppRepository _configuracaoRepository;
  final VoicePermissionService _permissionService;
  final AppThemeController _themeController;

  Future<VoiceGlobalCommandResult> execute(CommandResult command) async {
    switch (command.type) {
      case VoiceCommandType.ativarControleVoz:
        return _ativarControleVoz();
      case VoiceCommandType.desativarControleVoz:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(
            comandosVozAtivos: false,
            escutaContinua: false,
          ),
          message: 'Controle por voz desativado.',
          shouldStopListening: true,
        );
      case VoiceCommandType.ativarEscutaContinua:
        return _ativarEscutaContinua();
      case VoiceCommandType.desativarEscutaContinua:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(escutaContinua: false),
          message: 'Escuta contínua desativada.',
          shouldStopListening: true,
        );
      case VoiceCommandType.ativarTemaEscuro:
        return _atualizarTema(temaEscuro: true);
      case VoiceCommandType.desativarTemaEscuro:
        return _atualizarTema(temaEscuro: false);
      case VoiceCommandType.ativarFeedbackSonoro:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(feedbackSonoro: true),
          message: 'Feedback sonoro ativado.',
        );
      case VoiceCommandType.desativarFeedbackSonoro:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(feedbackSonoro: false),
          message: 'Feedback sonoro desativado.',
        );
      case VoiceCommandType.ativarParadaSilencio:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(paradaSilencio: true),
          message: 'Parada por silêncio ativada.',
        );
      case VoiceCommandType.desativarParadaSilencio:
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(paradaSilencio: false),
          message: 'Parada por silêncio desativada.',
        );
      case VoiceCommandType.definirTempoSilencio:
        final segundos = int.tryParse(command.parametro ?? '');
        if (segundos == null) {
          return const VoiceGlobalCommandResult(
            handled: true,
            message: 'Diga o tempo de silêncio entre 3 e 12 segundos.',
          );
        }
        final normalizado = segundos.clamp(3, 12).toInt();
        return _atualizarConfiguracao(
          (configuracao) => configuracao.copyWith(
            paradaSilencio: true,
            tempoSilencioSegundos: normalizado,
          ),
          message: 'Tempo de silêncio definido para $normalizado segundos.',
        );
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.confirmarAcao:
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.voltar:
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        return const VoiceGlobalCommandResult.notHandled();
    }
  }

  Future<VoiceGlobalCommandResult> _ativarControleVoz() async {
    final permissao = await _permissionService.requestMicrophone();
    if (permissao != VoicePermissionResult.granted) {
      return VoiceGlobalCommandResult(
        handled: true,
        message: permissao == VoicePermissionResult.permanentlyDenied
            ? 'Microfone bloqueado nas configurações do Android.'
            : 'Permissão de microfone negada.',
      );
    }

    return _atualizarConfiguracao(
      (configuracao) =>
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
      message: 'Controle por voz ativado.',
    );
  }

  Future<VoiceGlobalCommandResult> _ativarEscutaContinua() async {
    final permissao = await _permissionService.requestMicrophone();
    if (permissao != VoicePermissionResult.granted) {
      return VoiceGlobalCommandResult(
        handled: true,
        message: permissao == VoicePermissionResult.permanentlyDenied
            ? 'Microfone bloqueado nas configurações do Android.'
            : 'Permissão de microfone negada.',
      );
    }

    return _atualizarConfiguracao(
      (configuracao) =>
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
      message: 'Escuta contínua ativada.',
    );
  }

  Future<VoiceGlobalCommandResult> _atualizarTema({
    required bool temaEscuro,
  }) async {
    final resultado = await _atualizarConfiguracao(
      (configuracao) => configuracao.copyWith(temaEscuro: temaEscuro),
      message: temaEscuro ? 'Tema escuro ativado.' : 'Tema claro ativado.',
    );
    await _themeController.definirTemaEscuro(temaEscuro);
    return resultado;
  }

  Future<VoiceGlobalCommandResult> _atualizarConfiguracao(
    ConfiguracaoApp Function(ConfiguracaoApp configuracao) update, {
    required String message,
    bool shouldStopListening = false,
  }) async {
    final configuracao = await _configuracaoRepository.buscarConfiguracao();
    final atualizada = update(configuracao);
    await _configuracaoRepository.salvarConfiguracao(atualizada);

    return VoiceGlobalCommandResult(
      handled: true,
      message: message,
      shouldStopListening: shouldStopListening,
      updatedConfig: atualizada,
    );
  }
}
