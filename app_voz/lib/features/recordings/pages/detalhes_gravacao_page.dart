import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/historico_acao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/historico_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../editor/services/audio_player_service.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/services/command_service.dart';
import '../services/recording_management_service.dart';
import '../../voices/widgets/voice_command_help_dialog.dart';
import '../widgets/recording_status_chip.dart';
import 'minhas_gravacoes_page.dart';

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

class DetalhesGravacaoPage extends StatefulWidget {
  const DetalhesGravacaoPage({
    super.key,
    required this.usuario,
    required this.gravacaoId,
    @visibleForTesting this.recordingService,
    @visibleForTesting this.playerService,
    @visibleForTesting this.enableVoiceListening = true,
    @visibleForTesting this.onVoicePlaybackSuspendedForTesting,
    @visibleForTesting this.onVoicePlaybackResumeRequestedForTesting,
  });

  final Usuario usuario;
  final int gravacaoId;
  final RecordingManagementService? recordingService;
  final AudioPlayerService? playerService;
  final bool enableVoiceListening;
  final FutureOr<void> Function()? onVoicePlaybackSuspendedForTesting;
  final FutureOr<void> Function()? onVoicePlaybackResumeRequestedForTesting;

  @override
  State<DetalhesGravacaoPage> createState() => _DetalhesGravacaoPageState();
}

class _DetalhesGravacaoPageState extends State<DetalhesGravacaoPage>
    with ContextualVoiceListeningMixin<DetalhesGravacaoPage> {
  late final RecordingManagementService _recordingService;
  late final AudioPlayerService _playerService;
  final ScrollController _voiceScrollController = ScrollController();

  RecordingDetails? _details;
  List<HistoricoAcao> _historico = [];
  List<Gravacao> _gravacoesRelacionadas = [];
  bool _carregando = true;
  bool _reproduzindo = false;
  bool _alternandoReproducao = false;
  bool _salvandoNome = false;
  bool _excluindo = false;
  bool _retomadaEscutaPlaybackPendente = false;
  String? _erro;
  StreamSubscription? _playerStateSubscription;

  @override
  String get voiceOwnerId => VoicePageOwners.detalhesGravacao;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando da gravação...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  void initState() {
    super.initState();
    _recordingService = widget.recordingService ?? RecordingManagementService();
    _playerService = widget.playerService ?? AudioPlayerService();
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
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
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchContextualVoice,
    );
    _playerStateSubscription = _playerService.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }

      if (state.processingState == ProcessingState.completed ||
          (_reproduzindo &&
              !state.playing &&
              state.processingState == ProcessingState.idle)) {
        setState(() {
          _reproduzindo = false;
        });
        unawaited(_retomarEscutaAposPlayback());
      }
    });
    _carregarDados();
    if (widget.enableVoiceListening) {
      scheduleVoiceListeningOnFirstFrame();
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _playerStateSubscription?.cancel();
    _playerService.dispose();
    _voiceScrollController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final details = await _recordingService.loadDetails(widget.gravacaoId);
      if (details == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _details = null;
          _historico = [];
          _gravacoesRelacionadas = [];
          _carregando = false;
        });
        return;
      }

      final historico = details.gravacao.id == null
          ? <HistoricoAcao>[]
          : await HistoricoRepository.instance.listarPorGravacao(
              details.gravacao.id!,
            );
      final relacionadas = await _carregarGravacoesRelacionadas(
        details.gravacao,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _details = details;
        _historico = historico;
        _gravacoesRelacionadas = relacionadas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _erro = UserFacingMessages.dataLoadError;
        _carregando = false;
      });
    }
  }

  Future<List<Gravacao>> _carregarGravacoesRelacionadas(
    Gravacao gravacao,
  ) async {
    final projetoId = gravacao.projetoId;
    if (projetoId != null) {
      return _recordingService.listByProjectWithFileState(projetoId);
    }

    return _recordingService.listByUserWithFileState(gravacao.usuarioId);
  }

  Future<_PlaybackAction> _alternarReproducao() async {
    final gravacao = _details?.gravacao;
    if (gravacao == null) {
      return _PlaybackAction.none;
    }

    if (gravacao.status == GravacaoStatus.arquivoAusente ||
        gravacao.tamanhoBytes <= 0) {
      AppFeedback.showMessage(
        context,
        'Arquivo de áudio indisponível para reprodução.',
      );
      return _PlaybackAction.none;
    }

    setState(() {
      _alternandoReproducao = true;
    });

    try {
      if (_reproduzindo || _playerService.isPlaying) {
        await _playerService.stop();
        if (mounted) {
          setState(() {
            _reproduzindo = false;
          });
          voiceSetState(() {
            voiceStatusMessage = 'Reprodução parada.';
          });
        }
        await _retomarEscutaAposPlayback();
        return _PlaybackAction.stopped;
      }

      await _pausarEscutaParaPlayback();
      await _playerService.play(gravacao.caminhoArquivo);

      if (!mounted) {
        return _PlaybackAction.started;
      }

      setState(() {
        _reproduzindo = true;
      });
      voiceSetState(() {
        voiceStatusMessage = 'Reproduzindo ${gravacao.nome}.';
      });

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_reproduzida',
          descricao: 'Reproduziu a gravação "${gravacao.nome}" nos detalhes',
          gravacaoId: gravacao.id,
          projetoId: gravacao.projetoId,
        ),
      );
      return _PlaybackAction.started;
    } catch (e) {
      if (!mounted) {
        return _PlaybackAction.none;
      }

      AppFeedback.showMessage(context, UserFacingMessages.playbackError);
      await _retomarEscutaAposPlayback();
      return _PlaybackAction.none;
    } finally {
      if (mounted) {
        setState(() {
          _alternandoReproducao = false;
        });
      }
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

  Future<void> _renomearGravacao() async {
    final gravacao = _details?.gravacao;
    if (gravacao == null) {
      return;
    }

    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) => _RenomearGravacaoDialog(nomeInicial: gravacao.nome),
    );

    if (novoNome == null || novoNome.trim().isEmpty) {
      return;
    }

    await _salvarNovoNome(novoNome.trim(), origemVoz: false);
  }

  Future<void> _salvarNovoNome(
    String novoNome, {
    required bool origemVoz,
  }) async {
    final gravacao = _details?.gravacao;
    if (gravacao == null) {
      return;
    }

    setState(() {
      _salvandoNome = true;
    });

    try {
      final atualizada = await _recordingService.renameRecording(
        gravacao: gravacao,
        novoNome: novoNome,
        gravacoesRelacionadas: _gravacoesRelacionadas,
      );

      await _carregarDados();

      if (!mounted) {
        return;
      }

      voiceSetState(() {
        voiceStatusMessage = 'Gravação renomeada para ${atualizada.nome}.';
      });

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_renomeada',
          descricao:
              'Renomeou "${gravacao.nome}" para "${atualizada.nome}"${origemVoz ? ' por voz' : ''}',
          gravacaoId: gravacao.id,
          projetoId: gravacao.projetoId,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppFeedback.showMessage(
        context,
        'Não consegui renomear a gravação agora. Tente outro nome.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvandoNome = false;
        });
      }
    }
  }

  Future<void> _excluirGravacao() async {
    final gravacao = _details?.gravacao;
    if (gravacao == null) {
      return;
    }

    final confirmar = await showVoiceConfirmationDialog(
      id: 'delete_recording_details_${gravacao.id}',
      title: 'Excluir gravação',
      message: 'Deseja remover "${gravacao.nome}" do app e do dispositivo?',
      confirmLabel: 'Excluir',
      destructive: true,
    );

    if (confirmar != true) {
      return;
    }

    await _excluirConfirmada(origemVoz: false);
  }

  Future<void> _excluirConfirmada({required bool origemVoz}) async {
    final gravacao = _details?.gravacao;
    if (gravacao == null) {
      return;
    }

    var navegouAposExcluir = false;
    setState(() {
      _excluindo = true;
    });

    try {
      await _playerService.stop();
      await _recordingService.deleteRecording(gravacao);

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_excluida',
          descricao:
              'Excluiu a gravação "${gravacao.nome}"${origemVoz ? ' por voz' : ''}',
          projetoId: gravacao.projetoId,
        ),
      );

      if (!mounted) {
        return;
      }

      navegouAposExcluir = true;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || navegouAposExcluir) {
        return;
      }

      AppFeedback.showMessage(
        context,
        'Não consegui remover a gravação agora.',
      );
    } finally {
      if (mounted && !navegouAposExcluir) {
        setState(() {
          _excluindo = false;
        });
      }
    }
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoice(
    CommandResult resultado,
  ) async {
    switch (resultado.type) {
      case VoiceCommandType.reproduzirGravacao:
        final action = await _alternarReproducao();
        return VoiceCommandPageResult.handled(
          restartListening: action != _PlaybackAction.started,
        );
      case VoiceCommandType.pararReproducao:
        await _playerService.stop();
        if (mounted) {
          setState(() {
            _reproduzindo = false;
          });
        }
        await _retomarEscutaAposPlayback();
        return VoiceCommandPageResult.handled(message: 'Reprodução parada.');
      case VoiceCommandType.renomearGravacao:
        final novoNome = resultado.parametroSecundario;
        if (novoNome == null || novoNome.trim().isEmpty) {
          return VoiceCommandPageResult.handled(
            message: 'Diga: renomear gravação nome atual para novo nome.',
          );
        }
        await _salvarNovoNome(novoNome.trim(), origemVoz: true);
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.excluirGravacao:
        await _excluirGravacao();
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.confirmarAcao:
        return VoiceCommandPageResult.handled(
          message: 'Não há ação aguardando confirmação.',
        );
      case VoiceCommandType.cancelarAcao:
        return VoiceCommandPageResult.handled(message: 'Ação cancelada.');
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
      case VoiceCommandType.buscarGravacoes:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.buscarProjetos:
      case VoiceCommandType.limparBusca:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.excluirProjeto:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirAssistente:
        unawaited(openContextualVoiceHelp(VoiceCommandHelpContext.recordings));
        return VoiceCommandPageResult.handled(
          message: 'Aqui estão os comandos disponíveis.',
        );
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.abrirDetalhesGravacao:
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
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
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

  Future<VoiceCommandPageResult> _handleAbrirGravacoesGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
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

  Future<VoiceCommandPageResult> _navegarGlobal<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      await Navigator.push(context, route);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<void> _registrarHistorico({
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

  String _formatarData(String dataIso) {
    final data = DateTime.tryParse(dataIso);
    if (data == null) {
      return 'Data invalida';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano as $hora:$minuto';
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

  String _formatarTamanho(int bytes) {
    if (bytes <= 0) {
      return '0 KB';
    }

    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  String _formatarStatus(String status) {
    switch (status) {
      case GravacaoStatus.concluida:
        return 'Concluida';
      case GravacaoStatus.interrompida:
        return 'Interrompida';
      case GravacaoStatus.arquivoAusente:
        return 'Arquivo ausente';
      case GravacaoStatus.excluida:
        return 'Excluida';
      default:
        return 'Indefinida';
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da gravação'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDados,
        child: Builder(
          builder: (context) {
            if (_carregando) {
              return const AppLoadingView(
                message: 'Carregando detalhes da gravação...',
              );
            }

            if (_erro != null) {
              return ListView(
                controller: _voiceScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text(
                    _erro!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _carregarDados,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (details == null) {
              return ListView(
                controller: _voiceScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  const SizedBox(height: 80),
                  const AppEmptyState(
                    icon: Icons.music_off_outlined,
                    title: 'Gravação não encontrada',
                    subtitle:
                        'Esta gravação pode ter sido excluída ou não pertence mais ao banco local.',
                  ),
                ],
              );
            }

            return ListView(
              controller: _voiceScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          details.gravacao.nome,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        RecordingStatusChip(status: details.gravacao.status),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  _alternandoReproducao ||
                                      _salvandoNome ||
                                      _excluindo
                                  ? null
                                  : _alternarReproducao,
                              icon: _alternandoReproducao
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _reproduzindo
                                          ? Icons.stop_circle_outlined
                                          : Icons.play_circle_outline,
                                    ),
                              label: Text(_reproduzindo ? 'Parar' : 'Tocar'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _alternandoReproducao ||
                                      _salvandoNome ||
                                      _excluindo
                                  ? null
                                  : _renomearGravacao,
                              icon: _salvandoNome
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.edit_outlined),
                              label: const Text('Renomear'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _alternandoReproducao ||
                                      _salvandoNome ||
                                      _excluindo
                                  ? null
                                  : _excluirGravacao,
                              icon: _excluindo
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline),
                              label: const Text('Excluir'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoSection(
                  title: 'Arquivo',
                  children: [
                    _InfoRow(
                      label: 'Arquivo',
                      value: details.fileInfo.exists
                          ? 'Arquivo encontrado'
                          : 'Arquivo ausente',
                    ),
                    _InfoRow(
                      label: 'Status',
                      value: _formatarStatus(details.gravacao.status),
                    ),
                    _InfoRow(
                      label: 'Tamanho',
                      value: _formatarTamanho(details.gravacao.tamanhoBytes),
                    ),
                    _InfoRow(
                      label: 'Formato',
                      value: details.gravacao.formatoAudio.toUpperCase(),
                    ),
                    _InfoRow(
                      label: 'Local',
                      value: details.fileInfo.exists
                          ? 'Gravação local'
                          : 'Arquivo local não encontrado',
                    ),
                    _InfoRow(
                      label: 'Nome',
                      value: UserFacingMessages.fileName(details.fileInfo.path),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _InfoSection(
                  title: 'Metadados',
                  children: [
                    _InfoRow(
                      label: 'Data',
                      value: _formatarData(details.gravacao.dataCriacao),
                    ),
                    _InfoRow(
                      label: 'Duração',
                      value: _formatarDuracao(details.gravacao.duracaoSegundos),
                    ),
                    _InfoRow(
                      label: 'Projeto',
                      value: details.projeto?.nome ?? 'Sem projeto vinculado',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Histórico relacionado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_historico.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Nenhuma atividade registrada para esta gravação.',
                      ),
                    ),
                  )
                else
                  ..._historico
                      .take(8)
                      .map(
                        (item) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(item.descricao),
                            subtitle: Text(_formatarData(item.dataHora)),
                          ),
                        ),
                      ),
              ],
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

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _RenomearGravacaoDialog extends StatefulWidget {
  const _RenomearGravacaoDialog({required this.nomeInicial});

  final String nomeInicial;

  @override
  State<_RenomearGravacaoDialog> createState() =>
      _RenomearGravacaoDialogState();
}

class _RenomearGravacaoDialogState extends State<_RenomearGravacaoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.nomeInicial);
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
