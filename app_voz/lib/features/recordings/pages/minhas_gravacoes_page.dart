import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_search_field.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/gravacao_repository.dart';

class MinhasGravacoesPage extends StatefulWidget {
  final Usuario usuario;

  const MinhasGravacoesPage({super.key, required this.usuario});

  @override
  State<MinhasGravacoesPage> createState() => _MinhasGravacoesPageState();
}

class _MinhasGravacoesPageState extends State<MinhasGravacoesPage> {
  final List<Gravacao> _gravacoes = [];
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _carregando = true;
  bool _playerAberto = false;
  String? _erro;
  int? _gravacaoReproduzindoId;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _player.openPlayer();
      _playerAberto = true;
    } catch (e) {
      _erro = 'Erro ao inicializar player: $e';
    }

    await _carregarGravacoes();
  }

  void _onRecordingsStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarGravacoes() {
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
      if (!_playerAberto) {
        throw Exception('Player ainda não está pronto.');
      }

      if (_gravacaoReproduzindoId == gravacao.id) {
        await _player.stopPlayer();

        if (!mounted) {
          return;
        }

        setState(() {
          _gravacaoReproduzindoId = null;
        });
        return;
      }

      final arquivo = File(gravacao.caminhoArquivo);
      if (!await arquivo.exists()) {
        throw Exception('Arquivo não encontrado no aparelho.');
      }

      await _player.stopPlayer();
      await _player.startPlayer(
        fromURI: gravacao.caminhoArquivo,
        codec: Codec.aacMP4,
        whenFinished: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _gravacaoReproduzindoId = null;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _gravacaoReproduzindoId = gravacao.id;
      });
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
    final gravacaoId = gravacao.id;
    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) => _RenomearGravacaoDialog(nomeInicial: gravacao.nome),
    );

    if (novoNome == null || novoNome.isEmpty || gravacaoId == null) {
      return;
    }

    final gravacaoAtualizada = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      nome: novoNome,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
      motivoParada: gravacao.motivoParada,
      maiorPico: gravacao.maiorPico,
    );

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

    voiceSetState(() {
      voiceStatusMessage =
          'Gravacao renomeada para ${gravacaoAtualizada.nome}.';
    });
  }

  Future<void> _excluirGravacao(Gravacao gravacao) async {
    final gravacaoId = gravacao.id;
    final confirmar = await AppFeedback.confirm(
      context,
      title: 'Excluir gravação',
      message:
          'Deseja excluir "${gravacao.nome}" do banco de dados e do arquivo físico?',
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
      if (_gravacaoReproduzindoId == gravacao.id) {
        await _player.stopPlayer();
      }

      await GravacaoRepository.instance.removerGravacao(gravacao.id!);

      final arquivo = File(gravacao.caminhoArquivo);
      if (await arquivo.exists()) {
        await arquivo.delete();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _gravacoes.removeWhere((item) => item.id == gravacao.id);
        if (_gravacaoReproduzindoId == gravacao.id) {
          _gravacaoReproduzindoId = null;
        }
      });

      AppFeedback.showMessage(context, 'Gravação excluída com sucesso.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir a gravação: $e')),
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
      if (!mounted) {
        return;
      }

      await startContinuousVoiceListeningIfActive();
    }
  }

  @override
  void dispose() {
    _player.closePlayer();
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
            if (_carregando) {
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
                      processando: _confirmandoExclusaoPendente,
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
                        'Grave um áudio na tela Gravar áudio e ele aparecerá aqui automaticamente.',
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
                    processando: _confirmandoExclusaoPendente,
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
                          Text('Data: ${_formatarData(gravacao.dataCriacao)}'),
                          const SizedBox(height: 4),
                          Text(
                            'Duração: ${_formatarDuracao(gravacao.duracaoSegundos)}',
                          ),
                          if (gravacao.motivoParada != null) ...[
                            const SizedBox(height: 4),
                            Text('Parada: ${gravacao.motivoParada}'),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Maior pico: ${gravacao.maiorPico.toStringAsFixed(1)} dB',
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
                      },
                      itemBuilder: (context) => const [
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
