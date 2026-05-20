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
import '../../voices/coordination/voice_listening_coordinator.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_session_state.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/speech_service.dart';
import '../../voices/services/voice_global_command_service.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recording_service.dart';

enum EditorInteractionMode { normal, recording }

class EditorPage extends StatefulWidget {
  final Usuario usuario;
  final Projeto? projeto;

  const EditorPage({super.key, required this.usuario, this.projeto});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final SpeechService speech = SpeechService.instance;
  final VoiceListeningCoordinator _voiceCoordinator =
      VoiceListeningCoordinator.instance;
  static const String _voiceOwnerId = VoicePageOwners.editor;
  final CommandService commandService = const CommandService();
  final VoiceCommandController commandController = VoiceCommandController();
  final VoiceGlobalCommandService _globalCommandService =
      VoiceGlobalCommandService();
  final AudioRecordingService audioService = AudioRecordingService();
  final AudioPlayerService playerService = AudioPlayerService();
  final RecordingManagementService _recordingService =
      const RecordingManagementService();
  StreamSubscription? playerStateSubscription;

  bool ouvindo = false;
  bool gravando = false;
  bool pausado = false;
  bool reproduzindo = false;
  bool carregandoAudio = false;

  Timer? monitorSilencioTimer;

  double nivelAudioAtual = -160.0;
  int tempoSilencioMs = 0;

  int limiteSilencioMs = 6000;
  final int intervaloMonitoramentoMs = 500;
  final double limiteSilencioDb = -36.0;

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
  String? caminhoGravacaoAtual;
  DateTime? inicioGravacaoEm;

  final List<Gravacao> faixas = [];
  final List<String> historicoComandos = [];

  bool get _podeIniciarGravacao =>
      !gravando && !carregandoAudio && !reproduzindo;

  bool get _podePausarGravacao => gravando && !pausado && !carregandoAudio;

  bool get _podeRetomarGravacao => gravando && pausado && !carregandoAudio;

  bool get _podeEncerrarGravacao => gravando && !carregandoAudio;

  bool get _podeReproduzirAudio =>
      !gravando && !carregandoAudio && !reproduzindo && faixas.isNotEmpty;

  bool get _podePararAudio => reproduzindo && !carregandoAudio;

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
  }

  @override
  void initState() {
    super.initState();
    nomeProjeto = widget.projeto?.nome ?? nomeProjeto;
    playerStateSubscription = playerService.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }

      if (!state.playing && reproduzindo) {
        setState(() {
          reproduzindo = false;
          if (!carregandoAudio) {
            statusProjeto = 'Reprodução finalizada.';
          }
        });
      }
    });
    _carregarConfiguracoes();
    _carregarGravacoes();
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

    if (gravando || _voiceCoordinator.recordingModeActive) {
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

      if (!_voiceCoordinator.claimListening(_voiceOwnerId)) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.listening,
          message: 'Aguardando comando de voz.',
        );
        textoReconhecido = 'Ouvindo... fale um comando.';
        statusProjeto = 'Aguardando comando de voz...';
      });

      final started = await speech.startListening(
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
              reason: VoiceRestartReason.afterError,
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
        _voiceCoordinator.releaseOwner(_voiceOwnerId);
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
          reason: VoiceRestartReason.afterError,
        );
      }
    } else {
      _paradaManualEscuta = true;
      await speech.stopListening();

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
    VoiceRestartReason reason = VoiceRestartReason.normal,
  }) {
    _voiceCoordinator.scheduleContinuousRestart(
      ownerId: _voiceOwnerId,
      reason: reason,
      shouldRestart: () =>
          mounted &&
          escutaContinuaAtiva &&
          !_paradaManualEscuta &&
          !gravando &&
          !carregandoAudio &&
          !ouvindo &&
          !_voiceCoordinator.recordingModeActive,
      onRestart: alternarMicrofone,
    );
  }

  Future<void> _pausarEscutaParaModoGravacao() async {
    _paradaManualEscuta = false;
    _voiceCoordinator.enterRecordingMode();

    if (ouvindo || speech.isListening) {
      await speech.cancelListening();
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
    _voiceCoordinator.exitRecordingMode();

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
        !speech.isListening) {
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

      if (globalResult.shouldStopListening && (ouvindo || speech.isListening)) {
        await speech.cancelListening();
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

  Future<void> iniciarGravacao(String comando) async {
    if (gravando) {
      setState(() {
        statusProjeto = 'Já existe uma gravação em andamento.';
      });
      return;
    }

    if (carregandoAudio) {
      setState(() {
        statusProjeto = 'Aguarde o processamento atual terminar.';
      });
      return;
    }

    if (reproduzindo) {
      await pararReproducao('parar audio antes de gravar');
      if (!mounted) {
        return;
      }
    }

    _executandoComandoVoz = true;

    await _pausarEscutaParaModoGravacao();

    if (!mounted) {
      _executandoComandoVoz = false;
      return;
    }

    if (ouvindo || speech.isListening) {
      _paradaManualEscuta = false;
      await speech.cancelListening();
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) {
        _executandoComandoVoz = false;
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.recordingLocked,
          message: 'Escuta pausada para gravacao.',
        );
      });
    }

    if (reproduzindo) {
      await playerService.stop();

      if (!mounted) {
        _executandoComandoVoz = false;
        return;
      }

      setState(() {
        reproduzindo = false;
      });
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Preparando gravação...';
    });

    try {
      final path = await audioService.startRecording();

      if (!mounted) {
        return;
      }

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.recordingLocked,
          message: 'Microfone reservado para gravacao.',
        );
        caminhoGravacaoAtual = path;
        inicioGravacaoEm = DateTime.now();
        gravando = true;
        _interactionMode = EditorInteractionMode.recording;
        pausado = false;
        reproduzindo = false;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        nivelAudioAtual = -160.0;
        statusProjeto = 'Gravação real iniciada.';
        textoReconhecido = 'Gravação iniciada.';
      });

      iniciarMonitoramentoSilencio();

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Iniciou gravação real',
        tipo: 'gravacao_iniciada',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _setVoiceSession(
            VoiceSessionPhase.error,
            message: 'Erro ao iniciar gravacao.',
          );
          carregandoAudio = false;
          _interactionMode = EditorInteractionMode.normal;
          statusProjeto = 'Erro ao iniciar gravação: $e';
        });
        _retomarEscutaContinuaAposModoGravacao();
      }
    } finally {
      _executandoComandoVoz = false;
    }
  }

  Future<void> pausarGravacao(String comando) async {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para pausar.';
      });
      return;
    }

    if (pausado) {
      setState(() {
        statusProjeto = 'A gravação já está pausada.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Pausando gravação...';
    });

    try {
      await audioService.pauseRecording();
      pararMonitoramentoSilencio();
      if (!mounted) {
        return;
      }

      setState(() {
        pausado = true;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        statusProjeto = 'Gravação pausada.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Pausou gravação',
        tipo: 'gravacao_pausada',
      );
    } catch (e) {
      setState(() {
        carregandoAudio = false;
        statusProjeto = 'Erro ao pausar gravação: $e';
      });
    }
  }

  Future<void> retomarGravacao(String comando) async {
    if (!gravando || !pausado) {
      setState(() {
        statusProjeto = 'Não existe gravação pausada para retomar.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Retomando gravação...';
    });

    try {
      await audioService.resumeRecording();
      if (!mounted) {
        return;
      }

      setState(() {
        pausado = false;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        statusProjeto = 'Gravação retomada.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Retomou gravação',
        tipo: 'gravacao_retomada',
      );
      iniciarMonitoramentoSilencio();
    } catch (e) {
      setState(() {
        carregandoAudio = false;
        statusProjeto = 'Erro ao retomar gravação: $e';
      });
    }
  }

  Future<void> encerrarGravacao(String comando) async {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para encerrar.';
      });
      return;
    }

    pararMonitoramentoSilencio();

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Salvando gravação...';
    });

    try {
      final path = await audioService.stopRecording();

      if (path == null || path.isEmpty) {
        setState(() {
          _setVoiceSession(
            VoiceSessionPhase.error,
            message: 'Falha ao salvar gravacao.',
          );
          gravando = false;
          _interactionMode = EditorInteractionMode.normal;
          pausado = false;
          carregandoAudio = false;
          inicioGravacaoEm = null;
          statusProjeto = 'Não foi possível salvar a gravação.';
        });
        _retomarEscutaContinuaAposModoGravacao();
        return;
      }

      final usuarioId = widget.usuario.id;

      if (usuarioId == null) {
        setState(() {
          _setVoiceSession(
            VoiceSessionPhase.error,
            message: 'Usuario sem identificacao para salvar gravacao.',
          );
          gravando = false;
          _interactionMode = EditorInteractionMode.normal;
          pausado = false;
          carregandoAudio = false;
          caminhoGravacaoAtual = null;
          inicioGravacaoEm = null;
          tempoSilencioMs = 0;
          nivelAudioAtual = -160.0;
          statusProjeto = 'Usuário sem identificação para salvar a gravação.';
        });
        _retomarEscutaContinuaAposModoGravacao();
        return;
      }

      final numeroFaixa = faixas.length + 1;
      final nomeFaixa = _gerarNomeGravacaoUnico('Gravação $numeroFaixa');
      final agora = DateTime.now();
      final duracaoSegundos = inicioGravacaoEm == null
          ? 0
          : agora.difference(inicioGravacaoEm!).inSeconds;
      final gravacaoSalva = await _recordingService.createCompletedRecording(
        usuarioId: usuarioId,
        projetoId: widget.projeto?.id,
        nome: nomeFaixa,
        caminhoArquivo: path,
        dataCriacao: agora,
        duracaoSegundos: duracaoSegundos,
      );

      final foiParadaAutomatica = comando == 'parada automática por silêncio';

      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.idle,
          message: 'Gravacao finalizada.',
        );
        gravando = false;
        _interactionMode = EditorInteractionMode.normal;
        pausado = false;
        carregandoAudio = false;
        caminhoGravacaoAtual = null;
        inicioGravacaoEm = null;
        tempoSilencioMs = 0;
        nivelAudioAtual = -160.0;
        faixas.insert(0, gravacaoSalva);
        statusProjeto = foiParadaAutomatica
            ? '$nomeFaixa salva automaticamente após silêncio.'
            : '$nomeFaixa salva no projeto.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: foiParadaAutomatica
            ? 'Encerrou gravação por silêncio'
            : 'Encerrou gravação real e criou $nomeFaixa',
        tipo: foiParadaAutomatica
            ? 'gravacao_finalizada_por_silencio'
            : 'gravacao_finalizada',
        gravacaoId: gravacaoSalva.id,
        projetoId: gravacaoSalva.projetoId,
      );
    } catch (e) {
      setState(() {
        _setVoiceSession(
          VoiceSessionPhase.error,
          message: 'Erro ao encerrar gravacao.',
        );
        gravando = false;
        _interactionMode = EditorInteractionMode.normal;
        pausado = false;
        carregandoAudio = false;
        caminhoGravacaoAtual = null;
        inicioGravacaoEm = null;
        statusProjeto = 'Erro ao encerrar gravação: $e';
      });
    }
    _retomarEscutaContinuaAposModoGravacao();
  }

  void iniciarMonitoramentoSilencio() {
    monitorSilencioTimer?.cancel();

    tempoSilencioMs = 0;
    nivelAudioAtual = -160.0;

    monitorSilencioTimer = Timer.periodic(
      Duration(milliseconds: intervaloMonitoramentoMs),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (!gravando || pausado || carregandoAudio) {
          return;
        }

        if (!paradaAutomaticaPorSilencio) {
          return;
        }

        try {
          final amplitude = await audioService.getAmplitude();
          final nivelAtual = amplitude.current;
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            nivelAudioAtual = nivelAtual;
          });

          if (nivelAtual <= limiteSilencioDb) {
            tempoSilencioMs += intervaloMonitoramentoMs;
          } else {
            tempoSilencioMs = 0;
          }

          if (tempoSilencioMs >= limiteSilencioMs) {
            timer.cancel();

            if (mounted && gravando) {
              await encerrarGravacao('parada automática por silêncio');
            }
          }
        } catch (e) {
          debugPrint('Erro ao monitorar silêncio: $e');
        }
      },
    );
  }

  void pararMonitoramentoSilencio() {
    monitorSilencioTimer?.cancel();
    monitorSilencioTimer = null;
    tempoSilencioMs = 0;
  }

  Future<void> reproduzirProjeto(String comando) async {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Ainda não há gravações para reproduzir.';
      });
      return;
    }

    final ultimaFaixa = faixas.first;
    final caminho = ultimaFaixa.caminhoArquivo;
    final nome = ultimaFaixa.nome;

    if (caminho.isEmpty) {
      setState(() {
        statusProjeto = 'Arquivo da gravação não encontrado.';
      });
      return;
    }

    if (gravando) {
      setState(() {
        statusProjeto = 'Pare a gravação antes de reproduzir áudio.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Preparando reprodução...';
    });

    try {
      await playerService.play(caminho);
      if (!mounted) {
        return;
      }

      setState(() {
        reproduzindo = true;
        carregandoAudio = false;
        statusProjeto = 'Reproduzindo $nome.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Reproduziu gravação real',
        tipo: 'gravacao_reproduzida',
        gravacaoId: ultimaFaixa.id,
        projetoId: ultimaFaixa.projetoId,
      );
    } catch (e) {
      setState(() {
        reproduzindo = false;
        carregandoAudio = false;
        statusProjeto = 'Erro ao reproduzir áudio: $e';
      });
    }
  }

  Future<void> reproduzirFaixa(Gravacao faixa) async {
    final caminho = faixa.caminhoArquivo;
    final nome = faixa.nome;

    if (caminho.isEmpty) {
      setState(() {
        statusProjeto = 'Arquivo da gravação não encontrado.';
      });
      return;
    }

    if (gravando) {
      setState(() {
        statusProjeto = 'Pare a gravação antes de reproduzir áudio.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Preparando reprodução...';
    });

    try {
      await playerService.play(caminho);
      if (!mounted) {
        return;
      }

      setState(() {
        reproduzindo = true;
        carregandoAudio = false;
        statusProjeto = 'Reproduzindo $nome.';
      });

      adicionarHistorico(
        comandoOriginal: 'botão play da faixa',
        acao: 'Reproduziu $nome',
        tipo: 'gravacao_reproduzida',
        gravacaoId: faixa.id,
        projetoId: faixa.projetoId,
      );
    } catch (e) {
      setState(() {
        reproduzindo = false;
        carregandoAudio = false;
        statusProjeto = 'Erro ao reproduzir áudio: $e';
      });
    }
  }

  Future<void> pararReproducao(String comando) async {
    try {
      await playerService.stop();
      if (!mounted) {
        return;
      }

      setState(() {
        reproduzindo = false;
        statusProjeto = 'Reprodução parada.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Parou reprodução',
        tipo: 'reproducao_parada',
      );
    } catch (e) {
      setState(() {
        statusProjeto = 'Erro ao parar reprodução: $e';
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
    playerStateSubscription?.cancel();
    pararMonitoramentoSilencio();
    _voiceCoordinator.exitRecordingMode();
    unawaited(_voiceCoordinator.releaseAndStop(_voiceOwnerId));
    audioService.dispose();
    playerService.dispose();
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
                        tempoSilencioMs = 0;
                      });
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
