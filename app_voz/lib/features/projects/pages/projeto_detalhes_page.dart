import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../editor/pages/editor_page.dart';
import '../../history/pages/historico_page.dart';
import '../../recordings/pages/detalhes_gravacao_page.dart';
import '../../recordings/controllers/recordings_list_controller.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../recordings/widgets/recording_status_chip.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/services/command_service.dart';
import 'meus_projetos_page.dart';

const int _minRecordingNameLength = 2;
const int _maxRecordingNameLength = 80;

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

class ProjetoDetalhesPage extends StatefulWidget {
  final Usuario usuario;
  final Projeto projeto;

  const ProjetoDetalhesPage({
    super.key,
    required this.usuario,
    required this.projeto,
  });

  @override
  State<ProjetoDetalhesPage> createState() => _ProjetoDetalhesPageState();
}

class _ProjetoDetalhesPageState extends State<ProjetoDetalhesPage>
    with ContextualVoiceListeningMixin<ProjetoDetalhesPage> {
  final RecordingsListController _recordingsController =
      RecordingsListController();
  final ScrollController _voiceScrollController = ScrollController();

  StreamSubscription? _playerStateSubscription;
  int? _renomeandoGravacaoId;
  int? _excluindoGravacaoId;

  RecordingsListState get _recordingsState => _recordingsController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.projetoDetalhes;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando do projeto...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  void initState() {
    super.initState();
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
    _recordingsController.addListener(_onRecordingsStateChanged);
    _playerStateSubscription = _recordingsController.playerStateStream.listen((
      state,
    ) {
      if (!mounted) {
        return;
      }

      if (!state.playing) {
        _recordingsController.markPlaybackStopped();
      }
    });
    _carregarGravacoes();
    scheduleVoiceListeningOnFirstFrame();
  }

  void _onRecordingsStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarGravacoes() {
    return _recordingsController.loadByProject(projetoId: widget.projeto.id);
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

  int get _duracaoTotalSegundos => _recordingsState.recordings.fold(
    0,
    (total, item) => total + item.duracaoSegundos,
  );

  Future<void> _alternarReproducao(Gravacao gravacao) async {
    if (gravacao.status == GravacaoStatus.arquivoAusente ||
        gravacao.tamanhoBytes <= 0) {
      AppFeedback.showMessage(
        context,
        'Arquivo de áudio indisponível para reprodução.',
      );
      return;
    }

    try {
      await _recordingsController.togglePlayback(
        gravacao,
        usuarioId: widget.usuario.id,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(UserFacingMessages.playbackError)),
      );
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
        const SnackBar(content: Text('Não foi possível renomear a gravação.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _renomeandoGravacaoId = null;
        });
      }
    }
  }

  Future<void> _excluirGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    final confirmar = await showVoiceConfirmationDialog(
      id: 'delete_project_recording_$gravacaoId',
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

    try {
      await _recordingsController.deleteRecording(
        gravacao: gravacao,
        usuarioId: widget.usuario.id,
      );

      if (!mounted) {
        return;
      }

      AppFeedback.showMessage(
        context,
        'Gravação removida deste projeto com sucesso.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a gravação.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _excluindoGravacaoId = null;
        });
      }
    }
  }

  Future<void> _abrirEditor() async {
    await suspendContextualVoiceListening();

    if (!mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditorPage(usuario: widget.usuario, projeto: widget.projeto),
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
    _voiceScrollController.dispose();
    _playerStateSubscription?.cancel();
    _recordingsController.removeListener(_onRecordingsStateChanged);
    _recordingsController.dispose();
    super.dispose();
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoice(
    CommandResult resultado,
  ) async {
    switch (resultado.type) {
      case VoiceCommandType.abrirEditor:
        await _abrirEditor();
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.abrirDetalhesGravacao:
        return _handleAbrirDetalhesPorVoz(resultado.parametro);
      case VoiceCommandType.reproduzirGravacao:
        return _handleReproduzirPorNome(resultado.parametro);
      case VoiceCommandType.pararReproducao:
        await _recordingsController.stopPlayback();
        return VoiceCommandPageResult.handled(message: 'Reprodução parada.');
      case VoiceCommandType.renomearGravacao:
        return _handleRenomearPorVoz(
          resultado.parametro,
          resultado.parametroSecundario,
        );
      case VoiceCommandType.excluirGravacao:
        return _handleExcluirPorVoz(resultado.parametro);
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
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
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

  Future<VoiceCommandPageResult> _handleReproduzirPorNome(String? nome) async {
    final gravacao =
        _buscarGravacaoPorNome(nome) ??
        (_recordingsState.recordings.isNotEmpty
            ? _recordingsState.recordings.first
            : null);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma gravação encontrada para reproduzir.',
      );
    }

    await _alternarReproducao(gravacao);
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleAbrirDetalhesPorVoz(
    String? nome,
  ) async {
    final gravacao =
        _buscarGravacaoPorNome(nome) ??
        (_recordingsState.recordings.isNotEmpty
            ? _recordingsState.recordings.first
            : null);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma gravação encontrada para abrir detalhes.',
      );
    }

    await _abrirDetalhesGravacao(gravacao);
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleRenomearPorVoz(
    String? nomeAtual,
    String? novoNome,
  ) async {
    final gravacao = _buscarGravacaoPorNome(nomeAtual);

    if (gravacao == null || novoNome == null || novoNome.trim().isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga: renomear gravação nome atual para novo nome.',
      );
    }

    await _salvarNovoNomeGravacao(gravacao, novoNome.trim());
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleExcluirPorVoz(String? nome) async {
    final gravacao = _buscarGravacaoPorNome(nome);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Gravação não encontrada para exclusão.',
      );
    }

    await _excluirGravacao(gravacao);
    return VoiceCommandPageResult.handled();
  }

  Gravacao? _buscarGravacaoPorNome(String? nome) {
    return _recordingsController.findByName(nome);
  }

  Future<void> _salvarNovoNomeGravacao(
    Gravacao gravacao,
    String novoNome,
  ) async {
    if (gravacao.id == null) {
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

    voiceSetState(() {
      voiceStatusMessage =
          'Gravação renomeada para ${gravacaoAtualizada.nome}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projeto.nome),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirEditor,
        icon: const Icon(Icons.graphic_eq),
        label: const Text('Abrir editor'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarGravacoes,
        child: Builder(
          builder: (context) {
            final recordingsState = _recordingsState;
            final gravacoes = recordingsState.recordings;

            if (recordingsState.loading) {
              return const AppLoadingView(
                message: 'Carregando detalhes do projeto...',
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

            return ListView(
              controller: _voiceScrollController,
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Descrição',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (widget.projeto.descricao != null &&
                                  widget.projeto.descricao!.trim().isNotEmpty)
                              ? widget.projeto.descricao!
                              : 'Sem descrição cadastrada.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: _ResumoCard(
                                titulo: 'Gravações',
                                valor: gravacoes.length.toString(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _ResumoCard(
                                titulo: 'Duração total',
                                valor: _formatarDuracao(_duracaoTotalSegundos),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Gravações do projeto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (gravacoes.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: AppEmptyState(
                        icon: Icons.graphic_eq_outlined,
                        title: 'Ainda não há gravações neste projeto',
                        subtitle:
                            'Abra o editor e faça a primeira captura para começar a montar este projeto.',
                      ),
                    ),
                  ),
                if (gravacoes.isNotEmpty)
                  ...gravacoes.map((gravacao) {
                    final reproduzindo =
                        recordingsState.playingRecordingId == gravacao.id;
                    final processandoItem =
                        _renomeandoGravacaoId == gravacao.id ||
                        _excluindoGravacaoId == gravacao.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          onTap: processandoItem
                              ? null
                              : () => _abrirDetalhesGravacao(gravacao),
                          leading: IconButton(
                            onPressed: processandoItem
                                ? null
                                : () => _alternarReproducao(gravacao),
                            icon: Icon(
                              reproduzindo
                                  ? Icons.stop_circle
                                  : Icons.play_circle,
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
                                  'Data: ${_formatarData(gravacao.dataCriacao)}',
                                ),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : PopupMenuButton<String>(
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
                      ),
                    );
                  }),
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

class _ResumoCard extends StatelessWidget {
  final String titulo;
  final String valor;

  const _ResumoCard({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _RenomearGravacaoDialog extends StatefulWidget {
  final String nomeInicial;

  const _RenomearGravacaoDialog({required this.nomeInicial});

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
