import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_search_field.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/usuario.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../editor/pages/editor_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_confirmation_controller.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/coordination/voice_session_state.dart';
import '../../voices/services/command_service.dart';
import '../../voices/widgets/voice_command_help_dialog.dart';
import '../controllers/recordings_list_controller.dart';
import '../widgets/recording_status_chip.dart';
import 'detalhes_gravacao_page.dart';

const int _minRecordingNameLength = 2;
const int _maxRecordingNameLength = 80;

enum _PlaybackAction { none, started, stopped }

String? _validateRecordingName(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Informe o nome da gravação.';
  }
  if (trimmed.length < _minRecordingNameLength) {
    return 'O nome deve ter pelo menos 2 caracteres.';
  }
  if (trimmed.length > _maxRecordingNameLength) {
    return 'O nome deve ter no máximo 80 caracteres.';
  }
  return null;
}

class MinhasGravacoesPage extends StatefulWidget {
  final Usuario usuario;
  final RecordingsListController? recordingsController;
  final bool enableVoiceListening;
  final FutureOr<void> Function()? onVoicePlaybackSuspendedForTesting;
  final FutureOr<void> Function()? onVoicePlaybackResumeRequestedForTesting;

  const MinhasGravacoesPage({
    super.key,
    required this.usuario,
    @visibleForTesting this.recordingsController,
    @visibleForTesting this.enableVoiceListening = true,
    @visibleForTesting this.onVoicePlaybackSuspendedForTesting,
    @visibleForTesting this.onVoicePlaybackResumeRequestedForTesting,
  });

  @override
  State<MinhasGravacoesPage> createState() => _MinhasGravacoesPageState();
}

class _MinhasGravacoesPageState extends State<MinhasGravacoesPage>
    with ContextualVoiceListeningMixin<MinhasGravacoesPage> {
  late final RecordingsListController _recordingsController;
  final TextEditingController _buscaController = TextEditingController();
  final ScrollController _voiceScrollController = ScrollController();

  StreamSubscription? _playerStateSubscription;
  Timer? _buscaDebounce;
  int? _renomeandoGravacaoId;
  int? _excluindoGravacaoId;
  bool _confirmandoExclusaoPendente = false;
  bool _retomadaEscutaPlaybackPendente = false;
  bool _playerWasPlaying = false;
  TextEditingController? _renameModalController;
  // Monotonically-incrementing token; each new dispatch creates a new token.
  // A handler captures the token at entry and checks it before executing to
  // guard against stale transcripts that arrive after a newer command.
  int _commandToken = 0;

  RecordingsListState get _recordingsState => _recordingsController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.minhasGravacoes;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando de gravação...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  bool shouldUseAiForVoiceInput(String normalizedText) {
    return !_pareceReferenciaVisualDeGravacao(normalizedText);
  }

  @override
  void initState() {
    super.initState();
    _recordingsController =
        widget.recordingsController ?? RecordingsListController();
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.recordings,
      goHome: _handleIrParaHome,
      openProjects: _handleAbrirProjetosGlobal,
      openDashboard: _handleAbrirDashboardGlobal,
      openHistory: _handleAbrirHistoricoGlobal,
      openSettings: _handleAbrirConfiguracoesGlobal,
      openEditor: _handleAbrirEditorGlobal,
      openNewProject: _handleAbrirNovoProjetoGlobal,
      goBack: _handleVoltarGlobal,
    );
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchContextualVoice,
    );
    _recordingsController.addListener(_onRecordingsStateChanged);
    _playerStateSubscription = _recordingsController.playerStateStream.listen((
      state,
    ) {
      if (!mounted) {
        return;
      }

      final wasPlaying = _playerWasPlaying;
      _playerWasPlaying = state.playing;

      _recordingsController.handlePlayerState(state);

      // Only resume STT when transitioning from playing to stopped/idle,
      // or on explicit completion — not on the initial idle state at page load.
      if (state.processingState == ProcessingState.completed ||
          (wasPlaying &&
              !state.playing &&
              state.processingState == ProcessingState.idle)) {
        unawaited(_retomarEscutaAposPlayback());
      }
    });
    _carregarGravacoes();
    if (widget.enableVoiceListening) {
      scheduleVoiceListeningOnFirstFrame();
    }
  }

  void _onRecordingsStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarGravacoes() {
    return _recordingsController.load(
      usuarioId: widget.usuario.id,
      searchTerm: _buscaController.text,
    );
  }

  void _onBuscaAlterada(String termo) {
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _carregarGravacoes();
      }
    });
  }

  void _limparBusca() {
    if (_buscaController.text.isEmpty) {
      return;
    }

    _buscaDebounce?.cancel();
    _buscaController.clear();
    _carregarGravacoes();
  }

  String _formatarData(String dataIso) {
    final data = DateTime.tryParse(dataIso);

    if (data == null) {
      return 'Data inválida';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano às $hora:$minuto';
  }

  String _formatarDuracao(int segundos) {
    final horas = segundos ~/ 3600;
    final minutos = (segundos % 3600) ~/ 60;
    final segundosRestantes = segundos % 60;

    if (horas > 0) {
      return '${horas.toString().padLeft(2, '0')}:'
          '${minutos.toString().padLeft(2, '0')}:'
          '${segundosRestantes.toString().padLeft(2, '0')}';
    }

    return '${minutos.toString().padLeft(2, '0')}:'
        '${segundosRestantes.toString().padLeft(2, '0')}';
  }

  Future<_PlaybackAction> _alternarReproducao(Gravacao gravacao) async {
    if (gravacao.status == GravacaoStatus.arquivoAusente ||
        gravacao.tamanhoBytes <= 0) {
      AppFeedback.showMessage(
        context,
        'Arquivo de áudio indisponível para reprodução.',
      );
      return _PlaybackAction.none;
    }

    try {
      final jaEstavaReproduzindo =
          _recordingsController.state.playingRecordingId == gravacao.id;
      if (!jaEstavaReproduzindo) {
        await _pausarEscutaParaPlayback();
      }

      await _recordingsController.togglePlayback(
        gravacao,
        usuarioId: widget.usuario.id,
      );
      if (jaEstavaReproduzindo) {
        await _retomarEscutaAposPlayback();
        return _PlaybackAction.stopped;
      }

      return _PlaybackAction.started;
    } catch (e) {
      if (!mounted) {
        return _PlaybackAction.none;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(UserFacingMessages.playbackError)),
      );
      await _retomarEscutaAposPlayback();
      return _PlaybackAction.none;
    }
  }

  Future<void> _pausarEscutaParaPlayback() async {
    if (voiceOuvindo || voiceSessionManager.isSpeechListening) {
      await suspendContextualVoiceListening();
    }
    await widget.onVoicePlaybackSuspendedForTesting?.call();
  }

  Future<void> _retomarEscutaAposPlayback() async {
    if (_retomadaEscutaPlaybackPendente) {
      return;
    }

    _retomadaEscutaPlaybackPendente = true;
    try {
      await widget.onVoicePlaybackResumeRequestedForTesting?.call();
      if (!mounted || voiceParadaManual) {
        return;
      }
      scheduleVoiceContinuousRestart();
    } finally {
      _retomadaEscutaPlaybackPendente = false;
    }
  }

  Future<void> _renomearGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) => _RenomearGravacaoDialog(nomeInicial: gravacao.nome),
    );

    if (novoNome == null || novoNome.isEmpty || gravacaoId == null) {
      return;
    }

    setState(() {
      _renomeandoGravacaoId = gravacaoId;
    });

    try {
      await _recordingsController.renameRecording(
        gravacao: gravacao,
        newName: novoNome,
        usuarioId: widget.usuario.id,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não consegui renomear a gravação agora. Tente outro nome.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _renomeandoGravacaoId = null;
        });
      }
    }
  }

  Future<void> _salvarNovoNomeGravacao(
    Gravacao gravacao,
    String novoNome,
  ) async {
    if (novoNome.isEmpty || gravacao.id == null) {
      return;
    }

    final gravacaoAtualizada = await _recordingsController.renameRecording(
      gravacao: gravacao,
      newName: novoNome,
      usuarioId: widget.usuario.id,
      byVoice: true,
    );

    if (!mounted) {
      return;
    }

    debugPrint('[RenameVoice] listReloaded=true');
    voiceSetState(() {
      voiceStatusMessage =
          'Gravação renomeada para ${gravacaoAtualizada.nome}.';
    });
  }

  Future<void> _excluirGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    final confirmar = await showVoiceConfirmationDialog(
      id: 'delete_recording_$gravacaoId',
      title: 'Excluir gravação',
      message: 'Deseja remover "${gravacao.nome}" do app e do dispositivo?',
      confirmLabel: 'Excluir',
      destructive: true,
    );

    if (confirmar != true || gravacaoId == null) {
      return;
    }

    setState(() {
      _excluindoGravacaoId = gravacaoId;
    });

    setState(() {
      _confirmandoExclusaoPendente = true;
      _excluindoGravacaoId = gravacao.id;
    });

    try {
      await _recordingsController.deleteRecording(
        gravacao: gravacao,
        usuarioId: widget.usuario.id,
      );

      if (!mounted) {
        return;
      }

      AppFeedback.showMessage(context, 'Gravação removida do app.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui remover a gravação agora.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _excluindoGravacaoId = null;
        });
      }
    }
  }

  Future<void> _abrirDetalhesGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    if (gravacaoId == null) {
      AppFeedback.showMessage(context, 'Gravação sem identificação local.');
      return;
    }

    await suspendContextualVoiceListening();

    if (!mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalhesGravacaoPage(
          usuario: widget.usuario,
          gravacaoId: gravacaoId,
        ),
      ),
    );

    if (mounted) {
      await _carregarGravacoes();
      if (!mounted) {
        return;
      }

      await startContinuousVoiceListeningIfActive();
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _buscaDebounce?.cancel();
    _buscaController.dispose();
    _voiceScrollController.dispose();
    _playerStateSubscription?.cancel();
    _recordingsController.removeListener(_onRecordingsStateChanged);
    _recordingsController.dispose();
    // _renameModalController is disposed through the dialog's onDisposed callback
    // (fires after the exit animation, when the TextField has unmounted).
    // Setting to null here prevents stale writes if the page dies mid-animation.
    _renameModalController = null;
    super.dispose();
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoice(
    CommandResult resultado,
  ) async {
    final token = ++_commandToken;
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'raw=${resultado.originalText} '
      'parsedType=${resultado.type.name} '
      'dispatchStarted=true',
    );
    final result = await _dispatchContextualVoiceImpl(resultado, token);
    if (_commandToken == token) {
      debugPrint(
        '[RecordingsVoice] commandId=$token dispatchCompleted=true',
      );
    } else {
      debugPrint(
        '[RecordingsVoice] commandId=$token '
        'staleActionIgnored=true supersededBy=$_commandToken',
      );
    }
    return result;
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoiceImpl(
    CommandResult resultado,
    int token,
  ) async {
    switch (resultado.type) {
      case VoiceCommandType.abrirDetalhesGravacao:
        return _handleAbrirDetalhesPorVoz(resultado.parametro, token: token);
      case VoiceCommandType.reproduzirGravacao:
        return _handleReproduzirPorNome(resultado, token: token);
      case VoiceCommandType.pararReproducao:
        await _recordingsController.stopPlayback();
        await _retomarEscutaAposPlayback();
        return VoiceCommandPageResult.handled(message: 'Reprodução parada.');
      case VoiceCommandType.buscarGravacoes:
        return _buscarGravacoesPorVoz(resultado.parametro);
      case VoiceCommandType.limparBusca:
        _limparBusca();
        return VoiceCommandPageResult.handled(message: 'Busca limpa.');
      case VoiceCommandType.renomearGravacao:
        return _handleRenomearPorVoz(
          resultado.parametro,
          resultado.parametroSecundario,
          token: token,
        );
      case VoiceCommandType.excluirGravacao:
        return _handleExcluirPorVoz(resultado.parametro, token: token);
      case VoiceCommandType.confirmarAcao:
        return _handleConfirmarExclusaoPendente();
      case VoiceCommandType.cancelarAcao:
        voiceSetState(() {
          _recordingsController.cancelPendingDeletion();
          voiceStatusMessage = 'Exclusão cancelada.';
        });
        return VoiceCommandPageResult.handled(message: 'Exclusão cancelada.');
      case VoiceCommandType.preencherFraseComando:
        final renameCtrl = _renameModalController;
        if (renameCtrl != null && resultado.parametro != null) {
          renameCtrl.text = resultado.parametro!;
          debugPrint(
            '[RenameVoice] nameFilled=${resultado.parametro}',
          );
          debugPrint(
            '[RecordingsVoice] commandId=$token '
            'resolvedAction=renameFieldFill '
            'newName=${resultado.parametro}',
          );
          return VoiceCommandPageResult.handled(
            message:
                'Novo nome: "${resultado.parametro}". Diga confirmar para salvar.',
          );
        }
        return _handleReferenciaParcialDeGravacao(
          resultado.normalizedText,
          token: token,
        );
      case VoiceCommandType.scrollBaixo:
      case VoiceCommandType.scrollCima:
      case VoiceCommandType.scrollTopo:
      case VoiceCommandType.scrollFim:
        return await VoiceScrollHandler(
              controller: _voiceScrollController,
            ).handle(resultado) ??
            VoiceCommandPageResult.unavailable(
              recognized: resultado.recognized,
            );
      case VoiceCommandType.voltar:
        await suspendContextualVoiceListening();
        if (mounted) {
          Navigator.maybePop(context);
        }
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.buscarProjetos:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.excluirProjeto:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
        return VoiceCommandPageResult.handled(
          message: 'Você já está na tela de gravações.',
        );
      case VoiceCommandType.abrirAssistente:
        unawaited(openContextualVoiceHelp(VoiceCommandHelpContext.recordings));
        return VoiceCommandPageResult.handled(
          message: 'Aqui estão os comandos disponíveis.',
        );
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.ativarControleVoz:
      case VoiceCommandType.desativarControleVoz:
      case VoiceCommandType.ativarEscutaContinua:
      case VoiceCommandType.desativarEscutaContinua:
      case VoiceCommandType.ativarFeedbackSonoro:
      case VoiceCommandType.desativarFeedbackSonoro:
      case VoiceCommandType.ativarTemaEscuro:
      case VoiceCommandType.desativarTemaEscuro:
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
      case VoiceCommandType.comecarExperiencia:
      case VoiceCommandType.jaTenhoConta:
      case VoiceCommandType.permitirMicrofone:
      case VoiceCommandType.continuarFluxo:
      case VoiceCommandType.entrarConta:
      case VoiceCommandType.criarComandoPersonalizado:
      case VoiceCommandType.ativarComandoPersonalizado:
      case VoiceCommandType.desativarComandoPersonalizado:
      case VoiceCommandType.excluirComandoPersonalizado:
      case VoiceCommandType.salvarComandoPersonalizado:
      case VoiceCommandType.consultarTempoSilencio:
      case VoiceCommandType.ajustarTempoSilencio:
      case VoiceCommandType.consultarSensibilidadeSilencio:
      case VoiceCommandType.ajustarSensibilidadeSilencio:
      case VoiceCommandType.desconhecido:
        return _handleReferenciaParcialDeGravacao(
          resultado.normalizedText,
          token: token,
        );
      case VoiceCommandType.sair:
        return VoiceCommandPageResult.unavailable(
          recognized: resultado.recognized,
        );
    }
  }

  Future<VoiceCommandPageResult> _handleIrParaHome(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleVoltarGlobal(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetosGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjetoGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboardGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirHistoricoGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirConfiguracoesGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirEditorGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => EditorPage(usuario: widget.usuario)),
    );
  }

  Future<VoiceCommandPageResult> _navegarGlobal<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      await Navigator.push(context, route);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleReproduzirPorNome(
    CommandResult resultado, {
    required int token,
  }) async {
    final referencia = _referenciaPlaybackDoResultado(resultado);
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedAction=play '
      'resolvedRecordingRef=$referencia',
    );
    final resolution = _recordingsController.resolvePlaybackCommand(referencia);
    final gravacao = resolution.recording;
    if (gravacao == null) {
      return VoiceCommandPageResult.handled(message: resolution.message);
    }

    if (_commandToken != token) {
      debugPrint(
        '[RecordingsVoice] commandId=$token '
        'staleActionIgnored=true action=play supersededBy=$_commandToken',
      );
      return VoiceCommandPageResult.handled();
    }
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedRecordingId=${gravacao.id}',
    );
    final action = await _alternarReproducao(gravacao);
    return VoiceCommandPageResult.handled(
      restartListening: action != _PlaybackAction.started,
    );
  }

  String? _referenciaPlaybackDoResultado(CommandResult resultado) {
    final normalized = resultado.normalizedText;
    if (_pareceReferenciaVisualDeGravacao(normalized)) {
      return normalized;
    }

    return resultado.parametro;
  }

  // Verbos que iniciam um comando de renomeação — resultado parcial não deve
  // disparar reprodução enquanto a frase completa ainda está sendo reconhecida.
  static final _renameVerbPrefix = RegExp(
    r'^(renomear|nomear|mudar nome|alterar nome|trocar nome)',
  );

  // Matches "gravacao N" or "gravação N" (with or without accent) — these
  // appear as STT partial transcripts before "detalhes da gravacao N" or
  // "renomear gravacao N" arrive as final. Block playback and wait.
  static final _gravacaoNRef = RegExp(
    r'^grava(?:cao|ção) ([0-9]+|um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove)$',
  );

  Future<VoiceCommandPageResult> _handleReferenciaParcialDeGravacao(
    String referencia, {
    required int token,
  }) async {
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'raw=$referencia '
      'parsedType=desconhecido',
    );

    if (_renameVerbPrefix.hasMatch(referencia)) {
      // Rename verb prefix: wait for the full phrase before acting.
      return VoiceCommandPageResult.handled(
        message: voiceStatusMessage,
        restartListening: true,
      );
    }

    // "gravacao N" without a preceding action verb is almost always a partial
    // transcript (the user is saying "detalhes da gravacao N" or "renomear
    // gravacao N"). Never trigger playback here — wait for the full command.
    if (_gravacaoNRef.hasMatch(referencia)) {
      debugPrint(
        '[RecordingsVoice] commandId=$token '
        'raw=$referencia partialGravacaoRef=true waitingForFullCommand=true',
      );
      return VoiceCommandPageResult.handled(
        message: voiceStatusMessage,
        restartListening: true,
      );
    }

    final resolution = _recordingsController.resolvePlaybackCommand(referencia);
    final gravacao = resolution.recording;
    if (gravacao == null) {
      if (_pareceReferenciaVisualDeGravacao(referencia)) {
        return VoiceCommandPageResult.handled(message: resolution.message);
      }
      return VoiceCommandPageResult.unavailable(recognized: false);
    }

    if (_commandToken != token) {
      debugPrint(
        '[RecordingsVoice] commandId=$token '
        'staleActionIgnored=true action=play supersededBy=$_commandToken',
      );
      return VoiceCommandPageResult.handled();
    }
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedAction=play resolvedRecordingId=${gravacao.id}',
    );
    final action = await _alternarReproducao(gravacao);
    return VoiceCommandPageResult.handled(
      restartListening: action != _PlaybackAction.started,
    );
  }

  bool _pareceReferenciaVisualDeGravacao(String referencia) {
    return RegExp(
      r'(^| )(gravacao|item|posicao|posição|primeira|primeiro|segunda|segundo|terceira|terceiro|quarta|quarto|quinta|quinto|um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove)( |$)',
    ).hasMatch(referencia);
  }

  @visibleForTesting
  Future<VoiceCommandPageResult> debugHandleRecordingReferenceForTesting(
    String referencia,
  ) {
    return _handleReferenciaParcialDeGravacao(
      const CommandService().normalize(referencia),
      token: _commandToken,
    );
  }

  @visibleForTesting
  Future<VoiceCommandPageResult> debugHandleRenameForTesting(
    String nomeAtual,
    String novoNome,
  ) {
    return _handleRenomearPorVoz(
      const CommandService().normalize(nomeAtual),
      const CommandService().normalize(novoNome),
      token: _commandToken,
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirDetalhesPorVoz(
    String? nome, {
    required int token,
  }) async {
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedAction=details '
      'nome=${nome ?? "(vazio)"}',
    );

    // Bare "detalhes" with no reference: ask for clarification.
    if (nome == null || nome.trim().isEmpty) {
      return VoiceCommandPageResult.handled(
        message:
            'Qual gravação você deseja abrir? Diga, por exemplo, '
            '"detalhes do item 1" ou "detalhes da gravação 2".',
      );
    }

    final gravacao =
        _resolverGravacaoPorReferencia(nome) ?? _buscarGravacaoPorNome(nome);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: _recordingsState.recordings.isEmpty
            ? 'Não encontrei gravações. Grave um áudio no editor primeiro.'
            : 'Não encontrei "$nome". Diga o nome ou "detalhes do item 1".',
      );
    }

    if (_commandToken != token) {
      debugPrint(
        '[RecordingsVoice] commandId=$token '
        'staleActionIgnored=true action=details supersededBy=$_commandToken',
      );
      return VoiceCommandPageResult.handled();
    }
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedRecordingId=${gravacao.id}',
    );
    await _abrirDetalhesGravacao(gravacao);
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _buscarGravacoesPorVoz(String? termo) async {
    final termoBusca = termo?.trim() ?? '';
    if (termoBusca.isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga o termo para buscar nas gravações.',
      );
    }

    _buscaDebounce?.cancel();
    _buscaController.text = termoBusca;
    await _carregarGravacoes();
    return VoiceCommandPageResult.handled(
      message: 'Busca por $termoBusca aplicada nas gravações.',
    );
  }

  Future<VoiceCommandPageResult> _handleRenomearPorVoz(
    String? nomeAtual,
    String? novoNome, {
    required int token,
  }) async {
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedAction=rename '
      'nomeAtual=$nomeAtual novoNome=$novoNome',
    );

    // 1. Resolve exact reference ("gravacao N", "item N") before substring.
    // 2. Substring name fallback.
    // 3. Pure numeric index fallback.
    Gravacao? gravacao =
        _resolverGravacaoPorReferencia(nomeAtual) ??
        _buscarGravacaoPorNome(nomeAtual);

    if (gravacao == null && nomeAtual != null) {
      final index = int.tryParse(nomeAtual.trim());
      if (index != null && index > 0) {
        final recordings = _recordingsController.state.recordings;
        if (index <= recordings.length) {
          gravacao = recordings[index - 1];
        }
      }
    }

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message:
            'Não encontrei essa gravação. Diga o nome ou "renomear item 1".',
      );
    }

    // If novoNome is null (e.g. "renomear gravacao 2" without "para"),
    // open the modal pre-filled with the current name.
    final nomeParaModal = (novoNome?.trim().isNotEmpty == true)
        ? novoNome!.trim()
        : gravacao.nome;
    return _abrirModalRenomearComVoz(gravacao, nomeParaModal);
  }

  /// Abre o modal visual existente de renomeação pré-preenchido com [novoNomeSugerido].
  /// Enquanto o modal estiver aberto, voz "confirmar/sim/salvar" salva e
  /// "cancelar/voltar/não" descarta — outros comandos ficam bloqueados.
  Future<VoiceCommandPageResult> _abrirModalRenomearComVoz(
    Gravacao gravacao,
    String novoNomeSugerido,
  ) async {
    // Libera o flag de execução e agenda reinício do STT durante o dialog,
    // idêntico ao que showVoiceConfirmationDialog faz no mixin.
    voiceExecutandoComando = false;
    voiceIaPensando = false;
    voiceSessionState = voiceSessionState.transitionTo(
      VoiceSessionPhase.idle,
      message: voiceStatusMessage,
    );
    voiceSetState(() {
      voiceStatusMessage =
          'Diga "nome [novo nome]" para alterar, "confirmar" para salvar ou "cancelar".';
    });
    scheduleVoiceContinuousRestart();

    var completedByVoice = false;
    // Prevents double-pop if voice "confirmar" and button tap race each other.
    var dialogClosed = false;
    final externalController = TextEditingController(text: novoNomeSugerido);
    _renameModalController = externalController;
    debugPrint('[RenameVoice] modalOpened=true gravacaoId=${gravacao.id}');

    final novoNome = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        voiceConfirmationController.register(
          VoiceConfirmationRequest(
            id: 'renomear_gravacao_${gravacao.id}',
            description: 'Renomeação de "${gravacao.nome}"',
            onConfirm: () {
              if (dialogClosed) {
                debugPrint('[RenameVoice] duplicateCloseIgnored=true');
                return;
              }
              dialogClosed = true;
              completedByVoice = true;
              final nome = externalController.text.trim();
              debugPrint('[RenameVoice] confirmRequested=true nome=$nome');
              Navigator.pop(dialogContext, nome.isNotEmpty ? nome : null);
            },
            onCancel: () {
              if (dialogClosed) {
                debugPrint('[RenameVoice] duplicateCloseIgnored=true');
                return;
              }
              dialogClosed = true;
              completedByVoice = true;
              Navigator.pop(dialogContext, null);
            },
            destructive: false,
          ),
        );
        return _RenomearGravacaoDialog(
          nomeInicial: novoNomeSugerido,
          textController: externalController,
          // Dispose is deferred to after the exit animation completes —
          // calling dispose() here (while TextField is still mounted) would
          // trigger the _dependents.isEmpty assertion in ChangeNotifier.
          onDisposed: () {
            debugPrint('[RenameVoice] modalClosed=true');
            externalController.dispose();
          },
        );
      },
    );

    // The externalController is disposed asynchronously via onDisposed; do NOT
    // call dispose() here. Clear the page-level reference so new commands don't
    // try to write to a closing modal.
    _renameModalController = null;

    if (!completedByVoice) {
      voiceConfirmationController.clear();
    }

    // Re-agenda reinício do STT após fechar o dialog (sessão pode ter expirado).
    if (mounted) {
      scheduleVoiceContinuousRestart();
    }

    if (novoNome == null || novoNome.isEmpty) {
      return VoiceCommandPageResult.handled();
    }

    debugPrint('[RenameVoice] saveStarted=true novoNome=$novoNome');
    await _salvarNovoNomeGravacao(gravacao, novoNome);
    debugPrint('[RenameVoice] saveCompleted=true');
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleExcluirPorVoz(
    String? nome, {
    required int token,
  }) async {
    debugPrint(
      '[RecordingsVoice] commandId=$token '
      'resolvedAction=delete nome=$nome',
    );
    final gravacao =
        _resolverGravacaoPorReferencia(nome) ?? _buscarGravacaoPorNome(nome);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message:
            'Não encontrei essa gravação. Diga o nome de uma gravação da lista.',
      );
    }

    _recordingsController.requestDeletion(gravacao);
    voiceSetState(() {
      voiceStatusMessage =
          'Confirmar exclusão de ${gravacao.nome}? Diga confirmar exclusão ou cancelar exclusão.';
    });
    return VoiceCommandPageResult.handled(
      message:
          'Confirmar exclusão de ${gravacao.nome}? Diga confirmar exclusão ou cancelar exclusão.',
    );
  }

  Future<VoiceCommandPageResult> _handleConfirmarExclusaoPendente() async {
    final gravacao = _recordingsState.pendingDeletion;

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message:
            'Não há gravação aguardando confirmação. Diga excluir gravação antes de confirmar.',
      );
    }

    if (gravacao.id == null) {
      voiceSetState(() {
        voiceStatusMessage = 'Não consegui remover essa gravação agora.';
      });
      _recordingsController.cancelPendingDeletion();
      return VoiceCommandPageResult.handled(
        message: 'Não consegui remover essa gravação agora.',
      );
    }

    setState(() {
      _confirmandoExclusaoPendente = true;
      _excluindoGravacaoId = gravacao.id;
    });

    try {
      await _recordingsController.deleteRecording(
        gravacao: gravacao,
        usuarioId: widget.usuario.id,
        byVoice: true,
      );

      if (!mounted) {
        return VoiceCommandPageResult.handled(
          message: 'Gravação ${gravacao.nome} excluída.',
        );
      }

      return VoiceCommandPageResult.handled(
        message: 'Gravação ${gravacao.nome} excluída.',
      );
    } catch (e) {
      if (!mounted) {
        return VoiceCommandPageResult.handled(
          message: 'Não consegui remover a gravação agora.',
        );
      }

      voiceSetState(() {
        voiceStatusMessage = 'Não consegui remover a gravação agora.';
      });
      _recordingsController.cancelPendingDeletion();
      return VoiceCommandPageResult.handled(
        message: 'Não consegui remover a gravação agora.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _confirmandoExclusaoPendente = false;
          _excluindoGravacaoId = null;
        });
      }
    }
  }

  Gravacao? _buscarGravacaoPorNome(String? nome) {
    return _recordingsController.findByName(nome);
  }

  Gravacao? _resolverGravacaoPorReferencia(String? referencia) {
    final valor = referencia?.trim();
    if (valor == null || valor.isEmpty) {
      return null;
    }
    return _recordingsController.resolvePlaybackCommand(valor).recording;
  }

  Future<void> _abrirAjudaComandosGravacoes() {
    return showVoiceCommandHelpDialog(
      context,
      contextType: VoiceCommandHelpContext.recordings,
    );
  }

  Widget _buildBuscaGravacoes() {
    return AppSearchField(
      controller: _buscaController,
      hintText: 'Buscar por nome ou formato',
      onChanged: _onBuscaAlterada,
      onClear: _limparBusca,
      enabled: !_recordingsState.loading,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Gravações'),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('recordings_voice_command_help_button'),
            tooltip: 'Comandos desta tela',
            onPressed: _abrirAjudaComandosGravacoes,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarGravacoes,
        child: Builder(
          builder: (context) {
            final recordingsState = _recordingsState;
            final gravacoes = recordingsState.recordings;
            final gravacaoPendenteExclusao = recordingsState.pendingDeletion;

            if (recordingsState.loading) {
              return const AppLoadingView(
                message: 'Carregando suas gravações...',
              );
            }

            if (recordingsState.error != null) {
              return ListView(
                controller: _voiceScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text(
                    recordingsState.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _carregarGravacoes,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (gravacoes.isEmpty) {
              return ListView(
                controller: _voiceScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildBuscaGravacoes(),
                  const SizedBox(height: AppSpacing.xl),
                  if (gravacaoPendenteExclusao != null) ...[
                    _ConfirmacaoExclusaoCard(
                      gravacao: gravacaoPendenteExclusao,
                      processando: _confirmandoExclusaoPendente,
                      onConfirmar: () {
                        unawaited(_handleConfirmarExclusaoPendente());
                      },
                      onCancelar: () {
                        _recordingsController.cancelPendingDeletion();
                        voiceSetState(() {
                          voiceStatusMessage = 'Exclusão cancelada.';
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  const SizedBox(height: 80),
                  const AppEmptyState(
                    icon: Icons.library_music_outlined,
                    title: 'Nenhuma gravação encontrada',
                    subtitle:
                        'Suas gravações aparecerão aqui. Abra o editor para registrar a primeira ideia.',
                  ),
                ],
              );
            }

            return ListView.separated(
              controller: _voiceScrollController,
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount:
                  gravacoes.length +
                  (gravacaoPendenteExclusao != null ? 1 : 0) +
                  1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildBuscaGravacoes();
                }

                if (gravacaoPendenteExclusao != null && index == 1) {
                  return _ConfirmacaoExclusaoCard(
                    gravacao: gravacaoPendenteExclusao,
                    processando: _confirmandoExclusaoPendente,
                    onConfirmar: () {
                      unawaited(_handleConfirmarExclusaoPendente());
                    },
                    onCancelar: () {
                      _recordingsController.cancelPendingDeletion();
                      voiceSetState(() {
                        voiceStatusMessage = 'Exclusão cancelada.';
                      });
                    },
                  );
                }

                final gravacaoIndex = gravacaoPendenteExclusao != null
                    ? index - 2
                    : index - 1;
                final gravacao = gravacoes[gravacaoIndex];
                final numeroVisual = gravacaoIndex + 1;
                final reproduzindo =
                    recordingsState.playingRecordingId == gravacao.id;
                final renomeando = _renomeandoGravacaoId == gravacao.id;
                final excluindo = _excluindoGravacaoId == gravacao.id;
                final processandoItem = renomeando || excluindo;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    onTap: processandoItem
                        ? null
                        : () => _abrirDetalhesGravacao(gravacao),
                    leading: IconButton(
                      tooltip: reproduzindo
                          ? 'Parar reprodução de ${gravacao.nome}'
                          : 'Reproduzir gravação ${gravacao.nome}',
                      onPressed: processandoItem
                          ? null
                          : () => _alternarReproducao(gravacao),
                      icon: Icon(
                        reproduzindo ? Icons.stop_circle : Icons.play_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 34,
                      ),
                    ),
                    title: Text(
                      gravacao.nome,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Item $numeroVisual da lista',
                            key: Key('recording_visual_number_$numeroVisual'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Diga: tocar item $numeroVisual'),
                          const SizedBox(height: 4),
                          Text('Data: ${_formatarData(gravacao.dataCriacao)}'),
                          const SizedBox(height: 4),
                          Text(
                            'Duração: ${_formatarDuracao(gravacao.duracaoSegundos)}',
                          ),
                          const SizedBox(height: 8),
                          RecordingStatusChip(
                            status: gravacao.status,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                    trailing: processandoItem
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            tooltip: 'Abrir ações da gravação ${gravacao.nome}',
                            onSelected: (value) {
                              if (value == 'rename') {
                                _renomearGravacao(gravacao);
                              }
                              if (value == 'delete') {
                                _excluirGravacao(gravacao);
                              }
                              if (value == 'details') {
                                _abrirDetalhesGravacao(gravacao);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'details',
                                child: Text('Detalhes'),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Renomear'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: voiceStatusMessage == null
          ? null
          : VoiceStatusBar(
              message: voiceStatusMessage!,
              listening: voiceOuvindo,
              thinking: voiceIaPensando,
            ),
    );
  }
}

class _RenomearGravacaoDialog extends StatefulWidget {
  final String nomeInicial;
  // Quando fornecido pelo caminho de voz, o controller externo é gerenciado
  // pelo chamador e NÃO deve ser descartado pelo dialog.
  final TextEditingController? textController;
  // Chamado em dispose() do State, APÓS a animação de saída completar e o
  // TextField ser desmontado — seguro para descartar o textController externo.
  final VoidCallback? onDisposed;

  const _RenomearGravacaoDialog({
    required this.nomeInicial,
    this.textController,
    this.onDisposed,
  });

  @override
  State<_RenomearGravacaoDialog> createState() =>
      _RenomearGravacaoDialogState();
}

class _ConfirmacaoExclusaoCard extends StatelessWidget {
  final Gravacao gravacao;
  final bool processando;
  final VoidCallback onConfirmar;
  final VoidCallback onCancelar;

  const _ConfirmacaoExclusaoCard({
    required this.gravacao,
    required this.processando,
    required this.onConfirmar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Excluir gravação',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Deseja excluir "${gravacao.nome}"?'),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: processando ? null : onCancelar,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: processando ? null : onConfirmar,
                    child: processando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Excluir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenomearGravacaoDialogState extends State<_RenomearGravacaoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late final bool _ownsController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.textController == null;
    _controller =
        widget.textController ?? TextEditingController(text: widget.nomeInicial);
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _focusNode.dispose();
    // Called after exit animation — safe to dispose the external controller
    // here because the TextField has already been unmounted.
    widget.onDisposed?.call();
    debugPrint('[RenameVoice] controllerDisposed=${!_ownsController}');
    super.dispose();
  }

  void _salvar() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renomear gravação'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _salvar(),
          decoration: const InputDecoration(labelText: 'Novo nome'),
          validator: _validateRecordingName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
