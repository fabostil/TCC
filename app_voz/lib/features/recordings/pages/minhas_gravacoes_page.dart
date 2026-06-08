import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_search_field.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/usuario.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/services/command_service.dart';
import '../controllers/recordings_list_controller.dart';
import '../widgets/recording_status_chip.dart';
import 'detalhes_gravacao_page.dart';

class MinhasGravacoesPage extends StatefulWidget {
  final Usuario usuario;

  const MinhasGravacoesPage({super.key, required this.usuario});

  @override
  State<MinhasGravacoesPage> createState() => _MinhasGravacoesPageState();
}

class _MinhasGravacoesPageState extends State<MinhasGravacoesPage>
    with ContextualVoiceListeningMixin<MinhasGravacoesPage> {
  final RecordingsListController _recordingsController =
      RecordingsListController();
  final TextEditingController _buscaController = TextEditingController();

  StreamSubscription? _playerStateSubscription;
  Timer? _buscaDebounce;

  RecordingsListState get _recordingsState => _recordingsController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.minhasGravacoes;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando de gravacao...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  void initState() {
    super.initState();
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

  Future<void> _alternarReproducao(Gravacao gravacao) async {
    if (gravacao.status == GravacaoStatus.arquivoAusente ||
        gravacao.tamanhoBytes <= 0) {
      AppFeedback.showMessage(
        context,
        'Arquivo de audio indisponivel para reproducao.',
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
        SnackBar(content: Text('Não foi possível reproduzir o áudio: $e')),
      );
    }
  }

  Future<void> _renomearGravacao(Gravacao gravacao) async {
    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) => _RenomearGravacaoDialog(nomeInicial: gravacao.nome),
    );

    if (novoNome == null || novoNome.isEmpty || gravacao.id == null) {
      return;
    }

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
        SnackBar(content: Text('Não foi possível renomear a gravação: $e')),
      );
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

    voiceSetState(() {
      voiceStatusMessage =
          'Gravacao renomeada para ${gravacaoAtualizada.nome}.';
    });
  }

  Future<void> _excluirGravacao(Gravacao gravacao) async {
    final confirmar = await AppFeedback.confirm(
      context,
      title: 'Excluir gravação',
      message:
          'Deseja excluir "${gravacao.nome}" do banco de dados e do arquivo físico?',
      confirmLabel: 'Excluir',
      destructive: true,
    );

    if (confirmar != true || gravacao.id == null) {
      return;
    }

    try {
      await _recordingsController.deleteRecording(
        gravacao: gravacao,
        usuarioId: widget.usuario.id,
      );

      if (!mounted) {
        return;
      }

      AppFeedback.showMessage(context, 'Gravação excluída com sucesso.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir a gravação: $e')),
      );
    }
  }

  Future<void> _abrirDetalhesGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    if (gravacaoId == null) {
      AppFeedback.showMessage(context, 'Gravacao sem identificacao local.');
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
      await startContinuousVoiceListeningIfActive();
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _buscaDebounce?.cancel();
    _buscaController.dispose();
    _playerStateSubscription?.cancel();
    _recordingsController.removeListener(_onRecordingsStateChanged);
    _recordingsController.dispose();
    super.dispose();
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoice(
    CommandResult resultado,
  ) async {
    switch (resultado.type) {
      case VoiceCommandType.abrirDetalhesGravacao:
        return _handleAbrirDetalhesPorVoz(resultado.parametro);
      case VoiceCommandType.reproduzirGravacao:
        return _handleReproduzirPorNome(resultado.parametro);
      case VoiceCommandType.pararReproducao:
        await _recordingsController.stopPlayback();
        return VoiceCommandPageResult.handled(message: 'Reproducao parada.');
      case VoiceCommandType.buscarGravacoes:
        return _buscarGravacoesPorVoz(resultado.parametro);
      case VoiceCommandType.limparBusca:
        _limparBusca();
        return VoiceCommandPageResult.handled(message: 'Busca limpa.');
      case VoiceCommandType.renomearGravacao:
        return _handleRenomearPorVoz(
          resultado.parametro,
          resultado.parametroSecundario,
        );
      case VoiceCommandType.excluirGravacao:
        return _handleExcluirPorVoz(resultado.parametro);
      case VoiceCommandType.confirmarAcao:
        return _handleConfirmarExclusaoPendente();
      case VoiceCommandType.cancelarAcao:
        voiceSetState(() {
          _recordingsController.cancelPendingDeletion();
          voiceStatusMessage = 'Exclusao cancelada.';
        });
        return VoiceCommandPageResult.handled(message: 'Exclusao cancelada.');
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
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
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
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        return VoiceCommandPageResult.unavailable(
          recognized: resultado.recognized,
        );
    }
  }

  Future<VoiceCommandPageResult> _handleReproduzirPorNome(String? nome) async {
    final gravacao =
        _buscarGravacaoPorNome(nome) ??
        (_recordingsState.recordings.isNotEmpty
            ? _recordingsState.recordings.first
            : null);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma gravacao encontrada para reproduzir.',
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
        message: 'Nenhuma gravacao encontrada para abrir detalhes.',
      );
    }

    await _abrirDetalhesGravacao(gravacao);
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _buscarGravacoesPorVoz(String? termo) async {
    final termoBusca = termo?.trim() ?? '';
    if (termoBusca.isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga o termo para buscar nas gravacoes.',
      );
    }

    _buscaDebounce?.cancel();
    _buscaController.text = termoBusca;
    await _carregarGravacoes();
    return VoiceCommandPageResult.handled(
      message: 'Busca por $termoBusca aplicada nas gravacoes.',
    );
  }

  Future<VoiceCommandPageResult> _handleRenomearPorVoz(
    String? nomeAtual,
    String? novoNome,
  ) async {
    final gravacao = _buscarGravacaoPorNome(nomeAtual);

    if (gravacao == null || novoNome == null || novoNome.trim().isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga: renomear gravacao nome atual para novo nome.',
      );
    }

    await _salvarNovoNomeGravacao(gravacao, novoNome.trim());
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleExcluirPorVoz(String? nome) async {
    final gravacao = _buscarGravacaoPorNome(nome);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Gravacao nao encontrada para exclusao.',
      );
    }

    _recordingsController.requestDeletion(gravacao);
    voiceSetState(() {
      voiceStatusMessage =
          'Confirmar exclusao de ${gravacao.nome}? Diga confirmar exclusao ou cancelar exclusao.';
    });
    return VoiceCommandPageResult.handled(
      message:
          'Confirmar exclusao de ${gravacao.nome}? Diga confirmar exclusao ou cancelar exclusao.',
    );
  }

  Future<VoiceCommandPageResult> _handleConfirmarExclusaoPendente() async {
    final gravacao = _recordingsState.pendingDeletion;

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma exclusao pendente para confirmar.',
      );
    }

    if (gravacao.id == null) {
      voiceSetState(() {
        voiceStatusMessage = 'Gravacao invalida para exclusao.';
      });
      _recordingsController.cancelPendingDeletion();
      return VoiceCommandPageResult.handled(
        message: 'Gravacao invalida para exclusao.',
      );
    }

    try {
      await _recordingsController.deleteRecording(
        gravacao: gravacao,
        usuarioId: widget.usuario.id,
        byVoice: true,
      );

      if (!mounted) {
        return VoiceCommandPageResult.handled(
          message: 'Gravacao ${gravacao.nome} excluida.',
        );
      }

      return VoiceCommandPageResult.handled(
        message: 'Gravacao ${gravacao.nome} excluida.',
      );
    } catch (e) {
      if (!mounted) {
        return VoiceCommandPageResult.handled(
          message: 'Nao foi possivel excluir a gravacao: $e',
        );
      }

      voiceSetState(() {
        voiceStatusMessage = 'Nao foi possivel excluir a gravacao: $e';
      });
      _recordingsController.cancelPendingDeletion();
      return VoiceCommandPageResult.handled(
        message: 'Nao foi possivel excluir a gravacao: $e',
      );
    }
  }

  Gravacao? _buscarGravacaoPorNome(String? nome) {
    return _recordingsController.findByName(nome);
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildBuscaGravacoes(),
                  const SizedBox(height: AppSpacing.xl),
                  if (gravacaoPendenteExclusao != null) ...[
                    _ConfirmacaoExclusaoCard(
                      gravacao: gravacaoPendenteExclusao,
                      onConfirmar: () {
                        unawaited(_handleConfirmarExclusaoPendente());
                      },
                      onCancelar: () {
                        _recordingsController.cancelPendingDeletion();
                        voiceSetState(() {
                          voiceStatusMessage = 'Exclusao cancelada.';
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
                        'Grave um áudio no editor e ele aparecerá aqui automaticamente.',
                  ),
                ],
              );
            }

            return ListView.separated(
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
                    onConfirmar: () {
                      unawaited(_handleConfirmarExclusaoPendente());
                    },
                    onCancelar: () {
                      _recordingsController.cancelPendingDeletion();
                      voiceSetState(() {
                        voiceStatusMessage = 'Exclusao cancelada.';
                      });
                    },
                  );
                }

                final gravacaoIndex = gravacaoPendenteExclusao != null
                    ? index - 2
                    : index - 1;
                final gravacao = gravacoes[gravacaoIndex];
                final reproduzindo =
                    recordingsState.playingRecordingId == gravacao.id;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    onTap: () => _abrirDetalhesGravacao(gravacao),
                    leading: IconButton(
                      onPressed: () => _alternarReproducao(gravacao),
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
                    trailing: PopupMenuButton<String>(
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
                        PopupMenuItem(value: 'rename', child: Text('Renomear')),
                        PopupMenuItem(value: 'delete', child: Text('Excluir')),
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

  const _RenomearGravacaoDialog({required this.nomeInicial});

  @override
  State<_RenomearGravacaoDialog> createState() =>
      _RenomearGravacaoDialogState();
}

class _ConfirmacaoExclusaoCard extends StatelessWidget {
  final Gravacao gravacao;
  final VoidCallback onConfirmar;
  final VoidCallback onCancelar;

  const _ConfirmacaoExclusaoCard({
    required this.gravacao,
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
                    onPressed: onCancelar,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirmar,
                    child: const Text('Excluir'),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renomear gravação'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
        decoration: const InputDecoration(labelText: 'Novo nome'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
