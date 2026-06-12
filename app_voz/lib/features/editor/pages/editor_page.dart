import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/configuracao_app.dart';
import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../../repositories/historico_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/services/recording_management_service.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/controllers/voice_command_controller.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/coordination/voice_session_state.dart';
import '../../voices/coordination/voice_state_machine.dart';
import '../../voices/realtime/nlu/voice_intent.dart';
import '../../voices/realtime/runtime/voice_realtime_ecosystem.dart';
import '../../voices/realtime/voice_realtime_event_bus.dart';
import '../../voices/realtime/voice_realtime_events.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/voice_global_command_service.dart';
import '../controllers/recording_realtime_coordinator.dart';

enum EditorInteractionMode { normal, recording }

enum _EditorFsmVisualState {
  sleeping,
  listeningCommand,
  processingCommand,
  error,
}

class EditorPage extends StatefulWidget {
  final Usuario usuario;
  final Projeto? projeto;

  const EditorPage({super.key, required this.usuario, this.projeto});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  final VoiceSessionManager _voiceSessionManager = VoiceSessionManager.instance;
  static const String _voiceOwnerId = VoicePageOwners.editor;
  static const bool _useStreamFirstMode = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );
  static final Random _secureRandom = Random.secure();
  final CommandService commandService = const CommandService();
  final VoiceCommandController commandController = VoiceCommandController();
  final VoiceGlobalCommandService _globalCommandService =
      VoiceGlobalCommandService();
  late final VoiceNavigationCommandHandler _navigationCommandHandler;
  final RecordingRealtimeCoordinator _recordingCoordinator =
      RecordingRealtimeCoordinator(ownerId: _voiceOwnerId);
  final RecordingManagementService _recordingService =
      RecordingManagementService();
  StreamSubscription<VoiceCommandInterpretedEvent>?
  _realtimeCommandSubscription;

  bool ouvindo = false;

  int limiteSilencioMs = 6000;

  bool paradaAutomaticaPorSilencio = true;
  bool escutaContinuaAtiva = false;
  bool feedbackSonoroAtivo = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  bool _interpretandoComando = false;
  bool _saidaEditorEmAndamento = false;
  bool _retomarEscutaAposPlayback = false;
  bool _recuperacaoPlaybackAgendada = false;
  bool _playbackAtivoNaUltimaAtualizacao = false;
  EditorInteractionMode _interactionMode = EditorInteractionMode.normal;
  VoiceSessionState _voiceSessionState = const VoiceSessionState.idle();
  final EditorVoiceFlowPolicy _voiceFlowPolicy = const EditorVoiceFlowPolicy();

  String textoReconhecido = 'Pressione o microfone e fale um comando.';
  String statusProjeto = 'Projeto pronto para gravar.';
  String nomeProjeto = 'Projeto sem nome';
  late final String _voiceSessionToken;

  final List<Gravacao> faixas = [];
  final List<String> historicoComandos = [];

  RecordingRealtimeState get recordingState => _recordingCoordinator.state;

  bool get gravando => recordingState.recording;

  bool get pausado => recordingState.paused;

  bool get reproduzindo => recordingState.playing;

  bool get carregandoAudio => recordingState.processing;

  double get nivelAudioAtual => recordingState.currentAmplitude;

  int get tempoSilencioMs => recordingState.silenceMs;

  String? get caminhoGravacaoAtual => recordingState.currentPath;

  double get progressoLinhaDoTempo => recordingState.timelineProgress;

  bool get _podeIniciarGravacao => recordingState.canStartRecording;

  bool get _podePausarGravacao => recordingState.canPauseRecording;

  bool get _podeRetomarGravacao => recordingState.canResumeRecording;

  bool get _podeEncerrarGravacao => recordingState.canStopRecording;

  bool get _podeReproduzirAudio => recordingState.canPlay && faixas.isNotEmpty;

  bool get _podePararAudio => recordingState.canStopPlayback;

  bool get _escutaBloqueadaPorGravacao =>
      !_useStreamFirstMode &&
      (_voiceSessionState.phase == VoiceSessionPhase.recordingLocked ||
          _interactionMode == EditorInteractionMode.recording);

  void _setVoiceSession(
    VoiceSessionPhase phase, {
    String? message,
    bool? listening,
  }) {
    _voiceSessionState = _voiceSessionState.transitionTo(
      phase,
      message: message,
    );
    ouvindo = listening ?? _voiceSessionState.isListening;
    _voiceSessionManager.stateMachine.transitionTo(
      phase._toVoiceState(),
      ownerId: _voiceOwnerId,
      message: message,
      reason: 'editor_${phase.diagnosticName}',
      force: true,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.other,
      goHome: _handleIrParaHome,
      openProjects: _handleAbrirProjetosGlobal,
      openRecordings: _handleAbrirGravacoesGlobal,
      openDashboard: _handleAbrirDashboardGlobal,
      openHistory: _handleAbrirHistoricoGlobal,
      openSettings: _handleAbrirConfiguracoesGlobal,
      openNewProject: _handleAbrirNovoProjetoGlobal,
      goBack: _handleVoltarGlobal,
    );
    _voiceSessionToken = _generateVoiceSessionToken();
    nomeProjeto = widget.projeto?.nome ?? nomeProjeto;
    _publishRealtimeContext();
    _realtimeCommandSubscription = VoiceRealtimeEventBus.instance
        .on<VoiceCommandInterpretedEvent>()
        .listen(_handleRealtimeCommandDuringRecording);
    _recordingCoordinator.addListener(_onRecordingStateChanged);
    _carregarConfiguracoes();
    _carregarGravacoes();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _publishRealtimeContext();
      return;
    }
    _clearRealtimeContext();
  }

  String _generateVoiceSessionToken() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _publishRealtimeContext() {
    if (!mounted) {
      return;
    }
    VoiceRealtimeEcosystem.instance.updateActiveContext(
      projectId: widget.projeto?.id?.toString(),
      userId: widget.usuario.id?.toString(),
      sessionToken: _voiceSessionToken,
    );
  }

  void _clearRealtimeContext() {
    VoiceRealtimeEcosystem.instance.clearActiveContext();
  }

  void _handleRealtimeCommandDuringRecording(
    VoiceCommandInterpretedEvent event,
  ) {
    if (!_useStreamFirstMode || !mounted || !gravando || carregandoAudio) {
      return;
    }

    final intent = event.intent;
    final shouldStopRecording =
        intent is CancelIntent ||
        (intent is PlaybackIntent && intent.action == 'stop');

    if (!shouldStopRecording) {
      return;
    }

    unawaited(encerrarGravacao(intent.rawText));
  }

  void _onRecordingStateChanged() {
    if (!mounted) {
      return;
    }

    final playbackFinalizado =
        _playbackAtivoNaUltimaAtualizacao && !recordingState.playing;
    _playbackAtivoNaUltimaAtualizacao = recordingState.playing;

    setState(() {
      statusProjeto = recordingState.statusMessage;
    });

    if (playbackFinalizado) {
      unawaited(_retomarEscutaContinuaAposPlayback());
    }
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final configuracao = await ConfiguracaoAppRepository.instance
          .buscarConfiguracao();

      if (!mounted) {
        return;
      }

      _aplicarConfiguracao(configuracao);
      if (configuracao.comandosVozAtivos &&
          configuracao.escutaContinua &&
          !gravando &&
          !ouvindo) {
        unawaited(alternarMicrofone());
      }
    } catch (e) {
      debugPrint('Erro ao carregar configuracoes do editor: $e');
    }
  }

  void _aplicarConfiguracao(ConfiguracaoApp configuracao) {
    _recordingCoordinator.applySettings(
      automaticSilenceStop: configuracao.paradaSilencio,
      silenceLimitMs: configuracao.tempoSilencioSegundos * 1000,
    );

    setState(() {
      paradaAutomaticaPorSilencio = configuracao.paradaSilencio;
      limiteSilencioMs = configuracao.tempoSilencioSegundos * 1000;
      escutaContinuaAtiva =
          configuracao.comandosVozAtivos && configuracao.escutaContinua;
      feedbackSonoroAtivo = configuracao.feedbackSonoro;
    });
  }

  Future<void> _carregarGravacoes() async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      return;
    }

    try {
      final projetoId = widget.projeto?.id;
      final gravacoes = projetoId != null
          ? await _recordingService.listByProjectWithFileState(projetoId)
          : await _recordingService.listByUserWithFileState(usuarioId);

      if (!mounted) {
        return;
      }

      setState(() {
        faixas
          ..clear()
          ..addAll(gravacoes);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusProjeto = 'Erro ao carregar gravações: $e';
      });
    }
  }

  Future<void> alternarMicrofone() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    if (!configuracao.comandosVozAtivos) {
      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.manualPaused,
          message: 'Comandos de voz desativados.',
        );
        textoReconhecido = 'Comandos de voz desativados.';
        statusProjeto =
            'Ative o controle por voz em Configurações para usar comandos.';
      });
      return;
    }

    if (gravando || _voiceSessionManager.recordingActive) {
      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.recordingLocked,
          message: _useStreamFirstMode
              ? 'Gravação usando stream compartilhado.'
              : 'Microfone reservado para gravação.',
        );
        _interactionMode = EditorInteractionMode.recording;
        textoReconhecido = _useStreamFirstMode
            ? 'Escuta realtime ativa durante a gravação.'
            : 'Escuta por voz pausada durante a gravação para evitar conflito de microfone.';
        statusProjeto = _useStreamFirstMode
            ? 'Gravação em andamento com escuta hands-free pelo mesmo stream de áudio.'
            : 'Durante a gravação, o microfone fica reservado para capturar áudio. Use os controles manuais ou a parada por silêncio.';
      });
      return;
    }

    if (!ouvindo) {
      _aplicarConfiguracao(configuracao);
      _paradaManualEscuta = false;

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.listening,
          message: 'Aguardando comando de voz.',
        );
        textoReconhecido = 'Ouvindo... fale um comando.';
        statusProjeto = 'Aguardando comando de voz...';
      });

      final started = await _voiceSessionManager.startListening(
        ownerId: _voiceOwnerId,
        onResult: (resultado) {
          setState(() {
            _setVoiceSession(
              VoiceSessionPhase.processingCommand,
              message: resultado,
              listening: ouvindo,
            );
            textoReconhecido = resultado;
            statusProjeto = 'Comando detectado: $resultado';
          });

          unawaited(interpretarComando(resultado));
        },
        onStatus: (status) {
          if (!mounted) {
            return;
          }

          if (status == 'listening') {
            setState(() {
              _setVoiceSession(
                VoiceSessionPhase.listening,
                message: 'Estou ouvindo.',
              );
              statusProjeto = 'Estou ouvindo...';
            });
          }

          if (status == 'done' || status == 'notListening') {
            setState(() {
              _setVoiceSession(
                VoiceSessionPhase.idle,
                message: 'Escuta finalizada.',
              );
            });

            _reiniciarEscutaContinuaSeNecessario();
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }

          if (error == 'error_speech_timeout') {
            setState(() {
              _setVoiceSession(
                VoiceSessionPhase.error,
                message: 'Tempo de escuta encerrado sem comando.',
              );
              textoReconhecido =
                  'Nenhuma fala detectada. Tente falar mais perto do microfone.';
              statusProjeto = 'Tempo de escuta encerrado sem comando.';
            });
            _reiniciarEscutaContinuaSeNecessario(
              reason: VoiceRecoveryReason.afterError,
            );
            return;
          }

          setState(() {
            _setVoiceSession(
              VoiceSessionPhase.error,
              message: 'Erro no reconhecimento de voz.',
            );
            statusProjeto = 'Erro no reconhecimento de voz: $error';
            textoReconhecido = 'Não foi possível reconhecer a fala.';
          });
        },
      );

      if (!started) {
        if (!mounted) {
          return;
        }

        setState(() {
          _setVoiceSession(
            VoiceSessionPhase.error,
            message: 'Falha ao iniciar escuta de voz.',
          );
          textoReconhecido = 'Nao foi possivel iniciar a escuta de voz.';
          statusProjeto = 'Verifique a permissao de microfone do app.';
        });
        _reiniciarEscutaContinuaSeNecessario(
          reason: VoiceRecoveryReason.afterError,
        );
      }
    } else {
      _paradaManualEscuta = true;
      await _voiceSessionManager.stopListening(_voiceOwnerId, manual: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.manualPaused,
          message: 'Escuta encerrada manualmente.',
        );
        textoReconhecido = 'Pressione o microfone e fale um comando.';
        statusProjeto = 'Escuta encerrada.';
      });
    }
  }

  void _reiniciarEscutaContinuaSeNecessario({
    VoiceRecoveryReason reason = VoiceRecoveryReason.normal,
  }) {
    _voiceSessionManager.scheduleRecovery(
      ownerId: _voiceOwnerId,
      reason: reason,
      shouldRecover: () =>
          mounted &&
          escutaContinuaAtiva &&
          !_paradaManualEscuta &&
          !gravando &&
          !carregandoAudio &&
          !ouvindo &&
          !_voiceSessionManager.recordingActive,
      onRecover: alternarMicrofone,
    );
  }

  Future<void> _pausarEscutaParaModoGravacao() async {
    _paradaManualEscuta = false;
    _voiceSessionManager.enterRecordingMode(
      ownerId: _voiceOwnerId,
      reason: 'editor_prepare_recording',
    );

    if (ouvindo || _voiceSessionManager.isSpeechListening) {
      await _voiceSessionManager.cancelListening(
        ownerId: _voiceOwnerId,
        reason: 'recording_mode',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _setVoiceSession(
        VoiceSessionPhase.recordingLocked,
        message: _useStreamFirstMode
            ? 'Escuta realtime mantida pelo stream de gravação.'
            : 'Escuta pausada para liberar o microfone.',
      );
      _interactionMode = EditorInteractionMode.recording;
      statusProjeto = 'Preparando modo gravação...';
      textoReconhecido = _useStreamFirstMode
          ? 'Escuta realtime ativa durante a gravação.'
          : 'Escuta por voz pausada para liberar o microfone.';
    });
  }

  Future<void> _retomarEscutaContinuaAposModoGravacao() async {
    _voiceSessionManager.exitRecordingMode(
      ownerId: _voiceOwnerId,
      reason: 'editor_recording_finished',
    );

    if (!mounted || _paradaManualEscuta || gravando || carregandoAudio) {
      return;
    }

    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    _aplicarConfiguracao(configuracao);

    setState(() {
      _setVoiceSession(
        VoiceSessionPhase.idle,
        message: 'Modo gravacao finalizado.',
      );
    });

    if (configuracao.comandosVozAtivos &&
        configuracao.escutaContinua &&
        !ouvindo &&
        !_voiceSessionManager.isSpeechListening) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted || gravando || carregandoAudio || ouvindo) {
          return;
        }

        unawaited(alternarMicrofone());
      });
    }
  }

  Future<bool> _confirmarSaidaEditor() async {
    if (!gravando && !carregandoAudio) {
      return true;
    }

    if (carregandoAudio || _saidaEditorEmAndamento) {
      return false;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gravacao em andamento'),
        content: const Text(
          'Existe uma gravacao em andamento. Deseja encerrar a gravacao e sair do editor?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar gravando'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Encerrar e sair'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      if (mounted) {
        _reiniciarEscutaContinuaSeNecessario();
      }
      return false;
    }

    _saidaEditorEmAndamento = true;
    await encerrarGravacao('sair do editor');
    _saidaEditorEmAndamento = false;

    return mounted && !gravando && !carregandoAudio;
  }

  Future<void> interpretarComando(String comando) async {
    if (_interpretandoComando) {
      return;
    }

    setState(() {
      _interpretandoComando = true;
      _setVoiceSession(
        VoiceSessionPhase.processingCommand,
        message: 'Interpretando comando.',
        listening: ouvindo,
      );
      statusProjeto = 'Interpretando comando...';
    });

    try {
      final resultadoController = await commandController.interpret(
        comando,
        usuarioId: widget.usuario.id,
        onAiStarted: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _setVoiceSession(
              VoiceSessionPhase.aiThinking,
              message: 'IA interpretando comando.',
              listening: ouvindo,
            );
            statusProjeto = 'IA pensando...';
          });
        },
      );
      final resultado = resultadoController.commandResult;

      if (resultado.normalizedText.isEmpty) {
        return;
      }

      if (resultado.recognized) {
        registrarComandoVoz(
          comando,
          tipoComando: resultado.tipoComando,
          acaoExecutada: resultado.acaoExecutada,
        );
      }

      if (_executandoComandoVoz) {
        return;
      }

      final globalResult = await _globalCommandService.execute(resultado);
      if (globalResult.handled) {
        if (!mounted) {
          return;
        }

        final updatedConfig = globalResult.updatedConfig;
        if (updatedConfig != null) {
          _aplicarConfiguracao(updatedConfig);
        }

        if (globalResult.shouldStopListening &&
            (ouvindo || _voiceSessionManager.isSpeechListening)) {
          await _voiceSessionManager.cancelListening(
            ownerId: _voiceOwnerId,
            reason: 'global_command_stop',
          );
        }

        setState(() {
          if (globalResult.shouldStopListening) {
            _setVoiceSession(
              VoiceSessionPhase.manualPaused,
              message: globalResult.message,
            );
          }
          statusProjeto = globalResult.message ?? statusProjeto;
        });

        if (!globalResult.shouldStopListening) {
          _reiniciarEscutaContinuaSeNecessario();
        }
        return;
      }

      final navigationResult = await _navigationCommandHandler.handle(
        resultado,
      );
      if (navigationResult != null) {
        if (!mounted) {
          return;
        }

        if (navigationResult.statusMessage != null) {
          setState(() {
            statusProjeto = navigationResult.statusMessage!;
          });
        }

        if (navigationResult.restartListening) {
          _reiniciarEscutaContinuaSeNecessario();
        }
        return;
      }

      if (gravando && resultado.type == VoiceCommandType.sair) {
        final podeSair = await _confirmarSaidaEditor();
        if (podeSair && mounted) {
          Navigator.maybePop(context);
        }
        return;
      }

      switch (resultado.type) {
        case VoiceCommandType.iniciarGravacao:
          await iniciarGravacao(comando);
          return;
        case VoiceCommandType.pausarGravacao:
          await pausarGravacao(comando);
          return;
        case VoiceCommandType.retomarGravacao:
          await retomarGravacao(comando);
          return;
        case VoiceCommandType.encerrarGravacao:
          await encerrarGravacao(comando);
          return;
        case VoiceCommandType.pararReproducao:
          await pararReproducao(comando);
          return;
        case VoiceCommandType.reproduzirGravacao:
          await reproduzirProjeto(comando);
          return;
        case VoiceCommandType.criarMarcador:
          criarMarcador(comando);
          return;
        case VoiceCommandType.limparTexto:
          limparTexto(comando);
          return;
        case VoiceCommandType.listarGravacoes:
          setState(() {
            statusProjeto = 'Lista de gravacoes disponivel nesta tela.';
          });
          return;
        case VoiceCommandType.buscarGravacoes:
        case VoiceCommandType.buscarProjetos:
        case VoiceCommandType.limparBusca:
        case VoiceCommandType.abrirEditor:
          setState(() {
            statusProjeto = 'Editor ja esta aberto.';
          });
          return;
        case VoiceCommandType.definirNomeProjeto:
        case VoiceCommandType.definirDescricaoProjeto:
        case VoiceCommandType.substituirNomeProjeto:
        case VoiceCommandType.substituirDescricaoProjeto:
        case VoiceCommandType.abrirProjetoPorNome:
        case VoiceCommandType.renomearProjeto:
        case VoiceCommandType.excluirProjeto:
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
        case VoiceCommandType.voltar:
        case VoiceCommandType.sair:
        case VoiceCommandType.renomearGravacao:
        case VoiceCommandType.excluirGravacao:
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
        case VoiceCommandType.confirmarAcao:
        case VoiceCommandType.cancelarAcao:
          setState(() {
            statusProjeto =
                'Comando de navegacao reconhecido. Use o assistente de voz para navegar.';
          });
          return;
        case VoiceCommandType.desconhecido:
          break;
      }

      registrarComandoVoz(
        comando,
        tipoComando: resultado.tipoComando,
        statusReconhecimento: resultado.statusReconhecimento,
      );

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Comando nao reconhecido',
        tipo: 'comando_nao_reconhecido',
      );

      setState(() {
        statusProjeto = 'Comando nao reconhecido.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _interpretandoComando = false;
        });
      }
    }
  }

  Future<Gravacao> _finalizarGravacao({
    required String path,
    required DateTime startedAt,
    required bool automatic,
  }) async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      throw StateError('Usuario sem identificacao para salvar gravacao.');
    }

    final numeroFaixa = faixas.length + 1;
    final nomeFaixa = _gerarNomeGravacaoUnico('Gravacao $numeroFaixa');
    final agora = DateTime.now();
    final gravacaoSalva = await _recordingService.createCompletedRecording(
      usuarioId: usuarioId,
      projetoId: widget.projeto?.id,
      nome: nomeFaixa,
      caminhoArquivo: path,
      dataCriacao: agora,
      duracaoSegundos: agora.difference(startedAt).inSeconds,
    );

    if (mounted) {
      setState(() {
        faixas.insert(0, gravacaoSalva);
      });
    }

    return gravacaoSalva;
  }

  Future<VoiceCommandPageResult> _handleIrParaHome(CommandResult result) async {
    return _navegarGlobal(
      result: result,
      onNavigate: () {
        Navigator.popUntil(context, (route) => route.isFirst);
      },
    );
  }

  Future<VoiceCommandPageResult> _handleVoltarGlobal(
    CommandResult result,
  ) async {
    if (gravando) {
      final podeSair = await _confirmarSaidaEditor();
      if (podeSair && mounted) {
        Navigator.maybePop(context);
      }
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    return _navegarGlobal(
      result: result,
      onNavigate: () {
        Navigator.maybePop(context);
      },
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetosGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjetoGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirGravacoesGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboardGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => DashboardPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirHistoricoGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => HistoricoPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirConfiguracoesGlobal(
    CommandResult result,
  ) async {
    return _navegarGlobal(
      result: result,
      route: MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _navegarGlobal<T>({
    CommandResult? result,
    Route<T>? route,
    VoidCallback? onNavigate,
  }) async {
    final decision = _voiceFlowPolicy.navigationDecision(
      recording: gravando,
      commandType: result?.type,
    );

    if (decision == EditorVoiceNavigationDecision.block) {
      return VoiceCommandPageResult.handled(
        message: _voiceFlowPolicy.recordingNavigationBlockedMessage,
      );
    }

    if (ouvindo || _voiceSessionManager.isSpeechListening) {
      await _voiceSessionManager.cancelListening(
        ownerId: _voiceOwnerId,
        reason: 'global_navigation',
      );
    }

    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    if (route != null) {
      await Navigator.push(context, route);
    } else {
      onNavigate?.call();
    }

    return VoiceCommandPageResult.handled(restartListening: false);
  }

  RecordingHistoryWriter _historicoDaGravacao(String comando) {
    return (acao, tipo, {recordingId, projectId}) {
      if (!mounted) {
        return;
      }

      adicionarHistorico(
        comandoOriginal: comando,
        acao: acao,
        tipo: tipo,
        gravacaoId: recordingId,
        projetoId: projectId,
      );
    };
  }

  Future<void> iniciarGravacao(String comando) async {
    _executandoComandoVoz = true;

    try {
      await _pausarEscutaParaModoGravacao();
      if (!mounted) {
        return;
      }

      await _recordingCoordinator.startRecording(
        finalizeRecording: _finalizarGravacao,
        onHistory: _historicoDaGravacao(comando),
        onAutomaticStop: _retomarEscutaContinuaAposModoGravacao,
      );

      if (!mounted) {
        return;
      }

      if (!recordingState.recording) {
        setState(() {
          _setVoiceSession(
            VoiceSessionPhase.idle,
            message: recordingState.statusMessage,
          );
          _interactionMode = EditorInteractionMode.normal;
          statusProjeto = recordingState.statusMessage;
        });
        unawaited(_retomarEscutaContinuaAposModoGravacao());
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.recordingLocked,
          message: 'Microfone reservado para gravacao.',
        );
        _interactionMode = EditorInteractionMode.recording;
        textoReconhecido = 'Gravacao iniciada.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.error,
          message: 'Erro ao iniciar gravacao.',
        );
        _interactionMode = EditorInteractionMode.normal;
        statusProjeto = 'Erro ao iniciar gravacao: $e';
      });
      unawaited(_retomarEscutaContinuaAposModoGravacao());
    } finally {
      _executandoComandoVoz = false;
    }
  }

  Future<void> pausarGravacao(String comando) async {
    try {
      await _recordingCoordinator.pauseRecording(
        onHistory: (acao, tipo) {
          if (!mounted) {
            return;
          }

          adicionarHistorico(comandoOriginal: comando, acao: acao, tipo: tipo);
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusProjeto = 'Erro ao pausar gravacao: $e';
      });
    }
  }

  Future<void> retomarGravacao(String comando) async {
    try {
      await _recordingCoordinator.resumeRecording(
        finalizeRecording: _finalizarGravacao,
        onHistory: _historicoDaGravacao(comando),
        onAutomaticStop: _retomarEscutaContinuaAposModoGravacao,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusProjeto = 'Erro ao retomar gravacao: $e';
      });
    }
  }

  Future<void> encerrarGravacao(String comando) async {
    final paradaAutomatica =
        comando == 'parada automatica por silencio' ||
        comando == 'parada automática por silêncio';

    try {
      await _recordingCoordinator.stopRecording(
        finalizeRecording: _finalizarGravacao,
        onHistory: _historicoDaGravacao(comando),
        automatic: paradaAutomatica,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.idle,
          message: 'Gravacao finalizada.',
        );
        _interactionMode = EditorInteractionMode.normal;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.error,
          message: 'Erro ao encerrar gravacao.',
        );
        _interactionMode = EditorInteractionMode.normal;
        statusProjeto = 'Erro ao encerrar gravacao: $e';
      });
    } finally {
      await _retomarEscutaContinuaAposModoGravacao();
    }
  }

  Future<void> reproduzirProjeto(String comando) async {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Ainda nao ha gravacoes para reproduzir.';
      });
      return;
    }

    final ultimaFaixa = faixas.first;
    await _reproduzirFaixa(
      ultimaFaixa,
      comandoOriginal: comando,
      acaoHistorico: 'Reproduziu gravacao real',
    );
  }

  Future<void> reproduzirFaixa(Gravacao faixa) async {
    await _reproduzirFaixa(
      faixa,
      comandoOriginal: 'botao play da faixa',
      acaoHistorico: 'Reproduziu ${faixa.nome}',
    );
  }

  Future<void> _reproduzirFaixa(
    Gravacao faixa, {
    required String comandoOriginal,
    required String acaoHistorico,
  }) async {
    _retomarEscutaAposPlayback =
        escutaContinuaAtiva && !_paradaManualEscuta && !gravando;

    if (ouvindo || _voiceSessionManager.isSpeechListening) {
      await _voiceSessionManager.cancelListening(
        ownerId: _voiceOwnerId,
        reason: 'editor_playback',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.idle,
          message: 'Escuta pausada durante a reproducao.',
          listening: false,
        );
      });
    }

    await _recordingCoordinator.play(
      path: faixa.caminhoArquivo,
      name: faixa.nome,
      emptyPathMessage: 'Arquivo da gravacao nao encontrado.',
      recordingActiveMessage: 'Pare a gravacao antes de reproduzir audio.',
      onHistory: () {
        if (!mounted) {
          return;
        }

        adicionarHistorico(
          comandoOriginal: comandoOriginal,
          acao: acaoHistorico,
          tipo: 'gravacao_reproduzida',
          gravacaoId: faixa.id,
          projetoId: faixa.projetoId,
        );
      },
    );

    if (!recordingState.playing) {
      unawaited(_retomarEscutaContinuaAposPlayback());
    }
  }

  Future<void> pararReproducao(String comando) async {
    try {
      await _recordingCoordinator.stopPlayback();
      if (!mounted) {
        return;
      }

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Parou reproducao',
        tipo: 'reproducao_parada',
      );
      unawaited(_retomarEscutaContinuaAposPlayback());
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusProjeto = 'Erro ao parar reproducao: $e';
      });
    }
  }

  Future<void> _retomarEscutaContinuaAposPlayback() async {
    if (!_retomarEscutaAposPlayback || _recuperacaoPlaybackAgendada) {
      return;
    }

    _recuperacaoPlaybackAgendada = true;
    try {
      if (!mounted || gravando || carregandoAudio || reproduzindo) {
        return;
      }

      _retomarEscutaAposPlayback = false;
      _reiniciarEscutaContinuaSeNecessario();
    } finally {
      _recuperacaoPlaybackAgendada = false;
    }
  }

  void criarMarcador(String comando) {
    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Criou marcador no projeto',
      tipo: 'marcador_criado',
    );

    setState(() {
      statusProjeto = 'Marcador criado no ponto atual.';
    });
  }

  void limparTexto(String comando) {
    setState(() {
      textoReconhecido = 'Pressione o microfone e fale um comando.';
      statusProjeto = 'Texto limpo.';
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Limpou texto reconhecido',
      tipo: 'texto_limpo',
    );
  }

  void adicionarHistorico({
    required String comandoOriginal,
    required String acao,
    String tipo = 'acao_executada',
    int? gravacaoId,
    int? projetoId,
  }) {
    final registro = '$acao - "$comandoOriginal"';

    setState(() {
      historicoComandos.insert(0, registro);
    });

    unawaited(
      _registrarHistoricoPersistente(
        tipo: tipo,
        descricao: registro,
        gravacaoId: gravacaoId,
        projetoId: projetoId ?? widget.projeto?.id,
      ),
    );
  }

  Future<void> _registrarHistoricoPersistente({
    required String tipo,
    required String descricao,
    int? gravacaoId,
    int? projetoId,
  }) async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      return;
    }

    try {
      await HistoricoRepository.instance.registrar(
        usuarioId: usuarioId,
        tipo: tipo,
        descricao: descricao,
        gravacaoId: gravacaoId,
        projetoId: projetoId,
      );
    } catch (e) {
      debugPrint('Erro ao registrar historico persistente: $e');
    }
  }

  void registrarComandoVoz(
    String comando, {
    required String tipoComando,
    String statusReconhecimento = 'reconhecido',
    String? acaoExecutada,
  }) {
    unawaited(
      _registrarComandoVozPersistente(
        comando,
        tipoComando: tipoComando,
        statusReconhecimento: statusReconhecimento,
        acaoExecutada: acaoExecutada,
      ),
    );
  }

  Future<void> _registrarComandoVozPersistente(
    String comando, {
    required String tipoComando,
    required String statusReconhecimento,
    String? acaoExecutada,
  }) async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      return;
    }

    try {
      await ComandoVozRepository.instance.registrar(
        usuarioId: usuarioId,
        textoReconhecido: comando,
        tipoComando: tipoComando,
        statusReconhecimento: statusReconhecimento,
        acaoExecutada: acaoExecutada,
      );
    } catch (e) {
      debugPrint('Erro ao registrar comando de voz: $e');
    }
  }

  Color get corStatus {
    if (gravando && !pausado) {
      return _EditorPalette.record;
    }

    if (pausado) {
      return _EditorPalette.warning;
    }

    if (reproduzindo) {
      return _EditorPalette.playback;
    }

    return _EditorPalette.cyan;
  }

  String get textoStatus {
    if (carregandoAudio) {
      return 'Processando';
    }

    if (_interpretandoComando) {
      return 'Interpretando';
    }

    if (gravando && !pausado) {
      return 'Gravando';
    }

    if (pausado) {
      return 'Pausado';
    }

    if (reproduzindo) {
      return 'Reproduzindo';
    }

    return 'Pronto';
  }

  _EditorFsmVisualState get _fsmVisualState {
    if (_interpretandoComando) {
      return _EditorFsmVisualState.processingCommand;
    }

    return switch (_voiceSessionState.phase) {
      VoiceSessionPhase.listening => _EditorFsmVisualState.listeningCommand,
      VoiceSessionPhase.processingCommand ||
      VoiceSessionPhase.aiThinking => _EditorFsmVisualState.processingCommand,
      VoiceSessionPhase.error => _EditorFsmVisualState.error,
      _ => _EditorFsmVisualState.sleeping,
    };
  }

  Color _fsmAccentFor(_EditorThemeColors colors) {
    return switch (_fsmVisualState) {
      _EditorFsmVisualState.sleeping => colors.muted,
      _EditorFsmVisualState.listeningCommand => _EditorPalette.cyan,
      _EditorFsmVisualState.processingCommand => _EditorPalette.playback,
      _EditorFsmVisualState.error => _EditorPalette.error,
    };
  }

  String get _fsmLabel {
    return switch (_fsmVisualState) {
      _EditorFsmVisualState.sleeping => 'sleeping',
      _EditorFsmVisualState.listeningCommand => 'listeningCommand',
      _EditorFsmVisualState.processingCommand => 'processingCommand',
      _EditorFsmVisualState.error => 'error',
    };
  }

  IconData get _fsmIcon {
    return switch (_fsmVisualState) {
      _EditorFsmVisualState.sleeping => Icons.radio_button_unchecked,
      _EditorFsmVisualState.listeningCommand => Icons.graphic_eq,
      _EditorFsmVisualState.processingCommand => Icons.sync,
      _EditorFsmVisualState.error => Icons.error_outline,
    };
  }

  String _gerarNomeGravacaoUnico(String nomeBase) {
    final nomesExistentes = faixas
        .map((gravacao) => commandService.normalize(gravacao.nome))
        .toSet();

    var candidato = nomeBase;
    var contador = 1;
    while (nomesExistentes.contains(commandService.normalize(candidato))) {
      candidato = '$nomeBase$contador';
      contador++;
    }

    return candidato;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingCoordinator.removeListener(_onRecordingStateChanged);
    unawaited(_realtimeCommandSubscription?.cancel());
    _voiceSessionManager.exitRecordingMode(
      ownerId: _voiceOwnerId,
      reason: 'editor_dispose',
    );
    _clearRealtimeContext();
    unawaited(_voiceSessionManager.stopListening(_voiceOwnerId));
    _recordingCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EditorThemeColors.of(context);
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: colors.background,
        colorScheme: theme.colorScheme.copyWith(
          primary: _EditorPalette.cyan,
          secondary: _EditorPalette.playback,
          surface: colors.panel,
          error: _EditorPalette.error,
        ),
      ),
      child: PopScope(
        canPop: !gravando && !carregandoAudio,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }

          final podeSair = await _confirmarSaidaEditor();
          if (podeSair && context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('Editor Musical'),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: colors.textPrimary,
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors.backgroundGradient,
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _cabecalhoProjeto(),
                        if (gravando) ...[
                          const SizedBox(height: 14),
                          _modoGravacaoAtivo(),
                        ],
                        const SizedBox(height: 14),
                        _linhaDoTempo(),
                        const SizedBox(height: 14),
                        _controlesManuais(),
                        const SizedBox(height: 14),
                        _painelVoz(),
                        const SizedBox(height: 14),
                        _listaFaixas(),
                        const SizedBox(height: 14),
                        _historico(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalhoProjeto() {
    final colors = _EditorThemeColors.of(context);
    final fsmAccent = _fsmAccentFor(colors);

    return _EditorPanel(
      accentColor: corStatus,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusOrb(color: corStatus, icon: Icons.graphic_eq),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeProjeto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusProjeto,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusPill(
                  label: textoStatus,
                  color: corStatus,
                  icon: gravando
                      ? Icons.fiber_manual_record
                      : reproduzindo
                      ? Icons.play_arrow_rounded
                      : Icons.check_circle_outline,
                ),
              ],
            ),
            if (caminhoGravacaoAtual != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  caminhoGravacaoAtual!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _VoiceFsmHeader(
              state: _fsmVisualState,
              accent: fsmAccent,
              icon: _fsmIcon,
              label: _fsmLabel,
              message: _voiceSessionState.message,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modoGravacaoAtivo() {
    final segundosSilencioRestantes =
        ((limiteSilencioMs - tempoSilencioMs) / 1000).ceil();
    final tempoSilencioSegundos = limiteSilencioMs ~/ 1000;

    return _EditorPanel(
      accentColor: pausado ? _EditorPalette.warning : _EditorPalette.record,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.fiber_manual_record,
              color: _EditorPalette.record,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              pausado ? 'GRAVAÇÃO PAUSADA' : 'GRAVANDO...',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _EditorPalette.record,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pausado
                  ? 'A gravação está pausada.'
                  : 'O microfone está sendo usado para capturar o áudio.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Nível atual: ${nivelAudioAtual.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (paradaAutomaticaPorSilencio && !pausado)
              Text(
                tempoSilencioMs > 0
                    ? 'Silêncio detectado. Parando em $segundosSilencioRestantes s...'
                    : 'Parada automática por silêncio ativada.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !_podePausarGravacao
                        ? null
                        : () => pausarGravacao('botão grande pausar'),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pausar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !_podeRetomarGravacao
                        ? null
                        : () => retomarGravacao('botão grande retomar'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Retomar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: !_podeEncerrarGravacao
                    ? null
                    : () => encerrarGravacao('botão grande parar'),
                icon: const Icon(Icons.stop, size: 32),
                label: const Text(
                  'PARAR GRAVAÇÃO',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _EditorPalette.record,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Parada automática por silêncio'),
              subtitle: Text(
                'Encerra após $tempoSilencioSegundos segundos em silêncio.',
              ),
              value: paradaAutomaticaPorSilencio,
              onChanged: carregandoAudio
                  ? null
                  : (value) {
                      setState(() {
                        paradaAutomaticaPorSilencio = value;
                      });
                      _recordingCoordinator.applySettings(
                        automaticSilenceStop: value,
                        silenceLimitMs: limiteSilencioMs,
                      );
                      unawaited(
                        ConfiguracaoAppRepository.instance
                            .atualizarParadaSilencio(value),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaDoTempo() {
    final colors = _EditorThemeColors.of(context);
    final progress = progressoLinhaDoTempo.clamp(0.0, 1.0);
    final accent = gravando
        ? _EditorPalette.record
        : reproduzindo
        ? _EditorPalette.playback
        : _EditorPalette.cyan;

    return _EditorPanel(
      accentColor: accent,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.timeline_rounded,
              title: 'Linha do tempo',
              subtitle: gravando
                  ? 'Captura em andamento'
                  : reproduzindo
                  ? 'Playback ativo'
                  : 'Pronta para a próxima tomada',
              color: accent,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('00:00', style: TextStyle(color: colors.textMuted)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 10,
                          backgroundColor: colors.track,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).round().clamp(0, 100)}%',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Representação visual simplificada do andamento do projeto.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlesManuais() {
    return _EditorPanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.tune_rounded,
              title: 'Controles',
              subtitle: 'Comandos manuais de apoio',
              color: _EditorPalette.cyan,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: !_podeIniciarGravacao
                      ? null
                      : () => iniciarGravacao('botão gravar'),
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Gravar'),
                ),
                ElevatedButton.icon(
                  onPressed: !_podePausarGravacao
                      ? null
                      : () => pausarGravacao('botão pausar'),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
                ElevatedButton.icon(
                  onPressed: !_podeRetomarGravacao
                      ? null
                      : () => retomarGravacao('botão retomar'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
                ElevatedButton.icon(
                  onPressed: !_podeEncerrarGravacao
                      ? null
                      : () => encerrarGravacao('botão parar'),
                  icon: const Icon(Icons.stop),
                  label: const Text('Parar'),
                ),
                OutlinedButton.icon(
                  onPressed: !_podeReproduzirAudio
                      ? null
                      : () => reproduzirProjeto('botão reproduzir'),
                  icon: const Icon(Icons.headphones),
                  label: const Text('Reproduzir'),
                ),
                OutlinedButton.icon(
                  onPressed: !_podePararAudio
                      ? null
                      : () => pararReproducao('botão parar reprodução'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Parar áudio'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _painelVoz() {
    final colors = _EditorThemeColors.of(context);
    final fsmAccent = _fsmAccentFor(colors);

    return _EditorPanel(
      accentColor: fsmAccent,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assistente de voz',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comandos: iniciar gravação, pausar gravação, retomar gravação, encerrar gravação, reproduzir, criar marcador.',
            ),
            const SizedBox(height: 16),
            if (_escutaBloqueadaPorGravacao) ...[
              const Chip(
                avatar: Icon(Icons.mic_off_outlined, size: 18),
                label: Text('Escuta pausada na gravação'),
              ),
              const SizedBox(height: 16),
            ],
            if (_interpretandoComando) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 16),
            ],
            if (escutaContinuaAtiva || feedbackSonoroAtivo) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (escutaContinuaAtiva)
                    const Chip(
                      avatar: Icon(Icons.hearing_outlined, size: 18),
                      label: Text('Escuta continua ativa'),
                    ),
                  if (feedbackSonoroAtivo)
                    const Chip(
                      avatar: Icon(Icons.volume_up_outlined, size: 18),
                      label: Text('Feedback sonoro ativo'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: fsmAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: fsmAccent.withValues(alpha: 0.22)),
              ),
              child: Text(
                textoReconhecido,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FloatingActionButton.extended(
                onPressed: carregandoAudio || gravando || _interpretandoComando
                    ? null
                    : alternarMicrofone,
                backgroundColor: ouvindo ? _EditorPalette.record : fsmAccent,
                foregroundColor: colors.functionalForeground,
                icon: Icon(
                  gravando
                      ? Icons.mic_off
                      : ouvindo
                      ? Icons.mic
                      : Icons.mic_none,
                ),
                label: Text(
                  gravando
                      ? _useStreamFirstMode
                            ? 'Hands-free ativo'
                            : 'Escuta pausada'
                      : ouvindo
                      ? 'Parar escuta'
                      : 'Falar comando',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaFaixas() {
    return _EditorPanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.library_music_outlined,
              title: 'Faixas do projeto',
              subtitle: 'Takes salvos nesta sessão',
              color: _EditorPalette.playback,
            ),
            const SizedBox(height: 12),
            if (faixas.isEmpty)
              const Text('Nenhuma gravação adicionada ainda.'),
            if (faixas.isNotEmpty)
              ...faixas.map(
                (faixa) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.audiotrack),
                  title: Text(faixa.nome),
                  subtitle: Text(
                    faixa.caminhoArquivo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: carregandoAudio
                        ? null
                        : () {
                            reproduzirFaixa(faixa);
                          },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historico() {
    return _EditorPanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Histórico de comandos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (historicoComandos.isEmpty)
              const Text('Nenhum comando executado ainda.'),
            if (historicoComandos.isNotEmpty)
              ...historicoComandos
                  .take(6)
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

abstract final class _EditorPalette {
  static const black = Color(0xFF020304);
  static const panel = Color(0xFF0B1016);
  static const panelSoft = Color(0xFF111822);
  static const border = Color(0xFF1E2A35);
  static const track = Color(0xFF18222C);
  static const textPrimary = Color(0xFFE7EEF5);
  static const textSecondary = Color(0xFFB8C4CF);
  static const textMuted = Color(0xFF74808A);
  static const muted = Color(0xFF66717B);
  static const cyan = Color(0xFF35A7FF);
  static const playback = Color(0xFF28D7FF);
  static const record = Color(0xFF55FFB4);
  static const warning = Color(0xFFFFB84D);
  static const error = Color(0xFFD64545);
}

class _EditorThemeColors {
  const _EditorThemeColors({
    required this.background,
    required this.backgroundGradient,
    required this.panel,
    required this.panelSoft,
    required this.recessed,
    required this.border,
    required this.track,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.muted,
    required this.functionalForeground,
  });

  final Color background;
  final List<Color> backgroundGradient;
  final Color panel;
  final Color panelSoft;
  final Color recessed;
  final Color border;
  final Color track;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color muted;
  final Color functionalForeground;

  static _EditorThemeColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }

  static const dark = _EditorThemeColors(
    background: _EditorPalette.black,
    backgroundGradient: [
      Color(0xFF05080C),
      Color(0xFF080B10),
      _EditorPalette.black,
    ],
    panel: _EditorPalette.panel,
    panelSoft: _EditorPalette.panelSoft,
    recessed: Color(0xAA020304),
    border: _EditorPalette.border,
    track: _EditorPalette.track,
    textPrimary: _EditorPalette.textPrimary,
    textSecondary: _EditorPalette.textSecondary,
    textMuted: _EditorPalette.textMuted,
    muted: _EditorPalette.muted,
    functionalForeground: _EditorPalette.black,
  );

  static const light = _EditorThemeColors(
    background: Color(0xFFF7F4FB),
    backgroundGradient: [
      Color(0xFFFFFFFF),
      Color(0xFFF7F4FB),
      Color(0xFFEDE5F5),
    ],
    panel: Color(0xFFFFFFFF),
    panelSoft: Color(0xFFF4EEF9),
    recessed: Color(0xFFF1EAF7),
    border: Color(0xFFDCD0E8),
    track: Color(0xFFE8DFEF),
    textPrimary: Color(0xFF21172E),
    textSecondary: Color(0xFF4C405A),
    textMuted: Color(0xFF756783),
    muted: Color(0xFF7D6E8C),
    functionalForeground: Color(0xFF061016),
  );
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({required this.child, this.accentColor});

  final Widget child;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = _EditorThemeColors.of(context);
    final accent = accentColor ?? colors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = _EditorThemeColors.of(context);

    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = _EditorThemeColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceFsmHeader extends StatelessWidget {
  const _VoiceFsmHeader({
    required this.state,
    required this.accent,
    required this.icon,
    required this.label,
    required this.message,
  });

  final _EditorFsmVisualState state;
  final Color accent;
  final IconData icon;
  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = _EditorThemeColors.of(context);
    final listening = state == _EditorFsmVisualState.listeningCommand;
    final processing = state == _EditorFsmVisualState.processingCommand;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panelSoft.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: listening ? 0.55 : 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: listening ? 0.16 : 0.05),
            blurRadius: listening ? 22 : 10,
          ),
        ],
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: processing ? 0.12 : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, turns, child) {
              return AnimatedRotation(
                turns: turns,
                duration: const Duration(milliseconds: 320),
                child: child,
              );
            },
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message?.isNotEmpty == true
                      ? message!
                      : 'Assistente aguardando estado de voz.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum EditorVoiceNavigationDecision { allow, block, confirmExit }

@visibleForTesting
class EditorVoiceFlowPolicy {
  const EditorVoiceFlowPolicy();

  String get recordingVoiceUnavailableMessage =>
      'Gravacao em andamento. Use os controles da tela para pausar ou encerrar.';

  String get recordingNavigationBlockedMessage =>
      'Ha uma gravacao em andamento. Encerre ou cancele antes de sair.';

  EditorVoiceNavigationDecision navigationDecision({
    required bool recording,
    VoiceCommandType? commandType,
  }) {
    if (!recording) {
      return EditorVoiceNavigationDecision.allow;
    }

    return switch (commandType) {
      VoiceCommandType.voltar ||
      VoiceCommandType.sair => EditorVoiceNavigationDecision.confirmExit,
      _ => EditorVoiceNavigationDecision.block,
    };
  }
}

extension on VoiceSessionPhase {
  VoiceState _toVoiceState() {
    return switch (this) {
      VoiceSessionPhase.idle => VoiceState.idle,
      VoiceSessionPhase.listening => VoiceState.listening,
      VoiceSessionPhase.processingCommand => VoiceState.processing,
      VoiceSessionPhase.aiThinking => VoiceState.processing,
      VoiceSessionPhase.manualPaused => VoiceState.paused,
      VoiceSessionPhase.recordingLocked => VoiceState.recording,
      VoiceSessionPhase.error => VoiceState.error,
    };
  }
}
