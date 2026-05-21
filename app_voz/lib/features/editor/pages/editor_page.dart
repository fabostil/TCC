import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/configuracao_app.dart';
import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../../repositories/historico_repository.dart';
import '../../recordings/services/recording_management_service.dart';
import '../../voices/controllers/voice_command_controller.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/coordination/voice_session_state.dart';
import '../../voices/coordination/voice_state_machine.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/voice_global_command_service.dart';
import '../controllers/recording_realtime_coordinator.dart';

enum EditorInteractionMode { normal, recording }

class EditorPage extends StatefulWidget {
  final Usuario usuario;
  final Projeto? projeto;

  const EditorPage({super.key, required this.usuario, this.projeto});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final VoiceSessionManager _voiceSessionManager = VoiceSessionManager.instance;
  static const String _voiceOwnerId = VoicePageOwners.editor;
  final CommandService commandService = const CommandService();
  final VoiceCommandController commandController = VoiceCommandController();
  final VoiceGlobalCommandService _globalCommandService =
      VoiceGlobalCommandService();
  final RecordingRealtimeCoordinator _recordingCoordinator =
      RecordingRealtimeCoordinator(ownerId: _voiceOwnerId);
  final RecordingManagementService _recordingService =
      const RecordingManagementService();

  bool ouvindo = false;

  int limiteSilencioMs = 6000;

  bool paradaAutomaticaPorSilencio = true;
  bool escutaContinuaAtiva = false;
  bool feedbackSonoroAtivo = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  bool _saidaEditorEmAndamento = false;
  EditorInteractionMode _interactionMode = EditorInteractionMode.normal;
  VoiceSessionState _voiceSessionState = const VoiceSessionState.idle();

  String textoReconhecido = 'Pressione o microfone e fale um comando.';
  String statusProjeto = 'Projeto pronto para gravar.';
  String nomeProjeto = 'Projeto sem nome';

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

  bool get _podeIniciarGravacao =>
      recordingState.canStartRecording;

  bool get _podePausarGravacao => recordingState.canPauseRecording;

  bool get _podeRetomarGravacao => recordingState.canResumeRecording;

  bool get _podeEncerrarGravacao => recordingState.canStopRecording;

  bool get _podeReproduzirAudio => recordingState.canPlay && faixas.isNotEmpty;

  bool get _podePararAudio => recordingState.canStopPlayback;

  bool get _escutaBloqueadaPorGravacao =>
      _voiceSessionState.phase == VoiceSessionPhase.recordingLocked ||
      _interactionMode == EditorInteractionMode.recording;

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
    nomeProjeto = widget.projeto?.nome ?? nomeProjeto;
    _recordingCoordinator.addListener(_onRecordingStateChanged);
    _carregarConfiguracoes();
    _carregarGravacoes();
  }

  void _onRecordingStateChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      statusProjeto = recordingState.statusMessage;
    });
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
          message: 'Microfone reservado para gravacao.',
        );
        _interactionMode = EditorInteractionMode.recording;
        textoReconhecido =
            'Escuta por voz pausada durante a gravação para evitar conflito de microfone.';
        statusProjeto =
            'Durante a gravação, o microfone fica reservado para capturar áudio. Use os controles manuais ou a parada por silêncio.';
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
        message: 'Escuta pausada para liberar o microfone.',
      );
      _interactionMode = EditorInteractionMode.recording;
      statusProjeto = 'Preparando modo gravação...';
      textoReconhecido = 'Escuta por voz pausada para liberar o microfone.';
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
        title: const Text('Sair do editor?'),
        content: const Text(
          'Existe uma gravacao em andamento. Para sair com seguranca, o app precisa salvar a gravacao antes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar gravando'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar e sair'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      return false;
    }

    _saidaEditorEmAndamento = true;
    await encerrarGravacao('sair do editor');
    _saidaEditorEmAndamento = false;

    return mounted && !gravando && !carregandoAudio;
  }

  Future<void> interpretarComando(String comando) async {
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

      if (!mounted) {
        return;
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

          adicionarHistorico(
            comandoOriginal: comando,
            acao: acao,
            tipo: tipo,
          );
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
    final paradaAutomatica = comando == 'parada automatica por silencio' ||
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusProjeto = 'Erro ao parar reproducao: $e';
      });
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
      return Colors.red;
    }

    if (pausado) {
      return Colors.orange;
    }

    if (reproduzindo) {
      return Colors.green;
    }

    return Colors.deepPurple;
  }

  String get textoStatus {
    if (carregandoAudio) {
      return 'Processando';
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
    _recordingCoordinator.removeListener(_onRecordingStateChanged);
    _voiceSessionManager.exitRecordingMode(
      ownerId: _voiceOwnerId,
      reason: 'editor_dispose',
    );
    unawaited(_voiceSessionManager.stopListening(_voiceOwnerId));
    _recordingCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
        appBar: AppBar(title: const Text('Editor Musical'), centerTitle: true),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cabecalhoProjeto(),
              if (gravando) ...[
                const SizedBox(height: 18),
                _modoGravacaoAtivo(),
              ],
              const SizedBox(height: 18),
              _linhaDoTempo(),
              const SizedBox(height: 18),
              _controlesManuais(),
              const SizedBox(height: 18),
              _painelVoz(),
              const SizedBox(height: 18),
              _listaFaixas(),
              const SizedBox(height: 18),
              _historico(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalhoProjeto() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: corStatus.withValues(alpha: 0.12),
              child: Icon(Icons.graphic_eq, color: corStatus, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nomeProjeto,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(statusProjeto, style: const TextStyle(fontSize: 15)),
                  if (caminhoGravacaoAtual != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      caminhoGravacaoAtual!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            Chip(
              label: Text(textoStatus),
              avatar: Icon(Icons.circle, size: 12, color: corStatus),
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

    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 56),
            const SizedBox(height: 12),
            Text(
              pausado ? 'GRAVAÇÃO PAUSADA' : 'GRAVANDO...',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red,
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
                  backgroundColor: Colors.red,
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Linha do tempo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('00:00'),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: gravando || reproduzindo ? 0.45 : 0.0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('03:00'),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                textoReconhecido,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FloatingActionButton.extended(
                onPressed: carregandoAudio || gravando
                    ? null
                    : alternarMicrofone,
                backgroundColor: ouvindo ? Colors.red : Colors.deepPurple,
                icon: Icon(
                  gravando
                      ? Icons.mic_off
                      : ouvindo
                      ? Icons.mic
                      : Icons.mic_none,
                ),
                label: Text(
                  gravando
                      ? 'Escuta pausada'
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Faixas do projeto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
