import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/gravacao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/gravacao_repository.dart';
import '../../../repositories/historico_repository.dart';
import '../../editor/services/audio_player_service.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/services/command_service.dart';
import 'detalhes_gravacao_page.dart';

class MinhasGravacoesPage extends StatefulWidget {
  final Usuario usuario;

  const MinhasGravacoesPage({super.key, required this.usuario});

  @override
  State<MinhasGravacoesPage> createState() => _MinhasGravacoesPageState();
}

class _MinhasGravacoesPageState extends State<MinhasGravacoesPage>
    with ContextualVoiceListeningMixin<MinhasGravacoesPage> {
  final CommandService _commandService = const CommandService();
  final List<Gravacao> _gravacoes = [];
  final AudioPlayerService _playerService = AudioPlayerService();

  bool _carregando = true;
  String? _erro;
  int? _gravacaoReproduzindoId;
  Gravacao? _gravacaoPendenteExclusao;
  StreamSubscription? _playerStateSubscription;

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
    _playerStateSubscription = _playerService.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }

      if (!state.playing) {
        setState(() {
          _gravacaoReproduzindoId = null;
        });
      }
    });
    _carregarGravacoes();
    scheduleVoiceListeningOnFirstFrame();
  }

  Future<void> _carregarGravacoes() async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Usuário sem identificação para buscar gravações.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final gravacoes = await GravacaoRepository.instance
          .listarGravacoesPorUsuario(usuarioId);

      if (!mounted) {
        return;
      }

      setState(() {
        _gravacoes
          ..clear()
          ..addAll(gravacoes);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar gravações: $e';
      });
    }
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
    try {
      if (_gravacaoReproduzindoId == gravacao.id && _playerService.isPlaying) {
        await _playerService.stop();

        if (!mounted) {
          return;
        }

        setState(() {
          _gravacaoReproduzindoId = null;
        });
        return;
      }

      await _playerService.play(gravacao.caminhoArquivo);

      if (!mounted) {
        return;
      }

      setState(() {
        _gravacaoReproduzindoId = gravacao.id;
      });

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_reproduzida',
          descricao: 'Reproduziu a gravação "${gravacao.nome}"',
          gravacaoId: gravacao.id,
          projetoId: gravacao.projetoId,
        ),
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

    final nomeFinal = _gerarNomeGravacaoUnico(novoNome, ignorarId: gravacao.id);
    final gravacaoAtualizada = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      projetoId: gravacao.projetoId,
      nome: nomeFinal,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
    );

    try {
      await GravacaoRepository.instance.atualizarGravacao(gravacaoAtualizada);

      if (!mounted) {
        return;
      }

      setState(() {
        final index = _gravacoes.indexWhere((item) => item.id == gravacao.id);
        if (index != -1) {
          _gravacoes[index] = gravacaoAtualizada;
        }
      });

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_renomeada',
          descricao: 'Renomeou "${gravacao.nome}" para "$nomeFinal"',
          gravacaoId: gravacao.id,
          projetoId: gravacao.projetoId,
        ),
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

    final nomeFinal = _gerarNomeGravacaoUnico(novoNome, ignorarId: gravacao.id);
    final gravacaoAtualizada = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      projetoId: gravacao.projetoId,
      nome: nomeFinal,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
    );

    await GravacaoRepository.instance.atualizarGravacao(gravacaoAtualizada);

    if (!mounted) {
      return;
    }

    setState(() {
      final index = _gravacoes.indexWhere((item) => item.id == gravacao.id);
      if (index != -1) {
        _gravacoes[index] = gravacaoAtualizada;
      }
    });
    voiceSetState(() {
      voiceStatusMessage = 'Gravacao renomeada para $nomeFinal.';
    });

    unawaited(
      _registrarHistorico(
        tipo: 'gravacao_renomeada',
        descricao: 'Renomeou "${gravacao.nome}" para "$nomeFinal" por voz',
        gravacaoId: gravacao.id,
        projetoId: gravacao.projetoId,
      ),
    );
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
      if (_gravacaoReproduzindoId == gravacao.id) {
        await _playerService.stop();
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

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_excluida',
          descricao: 'Excluiu a gravação "${gravacao.nome}"',
          projetoId: gravacao.projetoId,
        ),
      );
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
    _playerStateSubscription?.cancel();
    _playerService.dispose();
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
        await _playerService.stop();
        if (mounted) {
          setState(() {
            _gravacaoReproduzindoId = null;
          });
        }
        return VoiceCommandPageResult.handled(message: 'Reproducao parada.');
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
          _gravacaoPendenteExclusao = null;
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
      case VoiceCommandType.renomearProjeto:
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
        (_gravacoes.isNotEmpty ? _gravacoes.first : null);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma gravacao encontrada para reproduzir.',
      );
    }

    await _alternarReproducao(gravacao);
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleAbrirDetalhesPorVoz(String? nome) async {
    final gravacao =
        _buscarGravacaoPorNome(nome) ??
        (_gravacoes.isNotEmpty ? _gravacoes.first : null);

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma gravacao encontrada para abrir detalhes.',
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

    voiceSetState(() {
      _gravacaoPendenteExclusao = gravacao;
      voiceStatusMessage =
          'Confirmar exclusao de ${gravacao.nome}? Diga confirmar exclusao ou cancelar exclusao.';
    });
    return VoiceCommandPageResult.handled(
      message:
          'Confirmar exclusao de ${gravacao.nome}? Diga confirmar exclusao ou cancelar exclusao.',
    );
  }

  Future<VoiceCommandPageResult> _handleConfirmarExclusaoPendente() async {
    final gravacao = _gravacaoPendenteExclusao;

    if (gravacao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nenhuma exclusao pendente para confirmar.',
      );
    }

    if (gravacao.id == null) {
      voiceSetState(() {
        voiceStatusMessage = 'Gravacao invalida para exclusao.';
        _gravacaoPendenteExclusao = null;
      });
      return VoiceCommandPageResult.handled(
        message: 'Gravacao invalida para exclusao.',
      );
    }

    try {
      if (_gravacaoReproduzindoId == gravacao.id) {
        await _playerService.stop();
      }

      await GravacaoRepository.instance.removerGravacao(gravacao.id!);

      final arquivo = File(gravacao.caminhoArquivo);
      if (await arquivo.exists()) {
        await arquivo.delete();
      }

      if (!mounted) {
        return VoiceCommandPageResult.handled(
          message: 'Gravacao ${gravacao.nome} excluida.',
        );
      }

      setState(() {
        _gravacoes.removeWhere((item) => item.id == gravacao.id);
        _gravacaoPendenteExclusao = null;
        if (_gravacaoReproduzindoId == gravacao.id) {
          _gravacaoReproduzindoId = null;
        }
      });

      unawaited(
        _registrarHistorico(
          tipo: 'gravacao_excluida',
          descricao: 'Excluiu a gravacao "${gravacao.nome}" por voz',
          projetoId: gravacao.projetoId,
        ),
      );

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
        _gravacaoPendenteExclusao = null;
      });
      return VoiceCommandPageResult.handled(
        message: 'Nao foi possivel excluir a gravacao: $e',
      );
    }
  }

  Gravacao? _buscarGravacaoPorNome(String? nome) {
    final nomeNormalizado = _commandService.normalize(nome ?? '');
    if (nomeNormalizado.isEmpty) {
      return null;
    }

    for (final gravacao in _gravacoes) {
      if (_commandService.normalize(gravacao.nome).contains(nomeNormalizado)) {
        return gravacao;
      }
    }

    return null;
  }

  String _gerarNomeGravacaoUnico(String nomeBase, {int? ignorarId}) {
    final base = nomeBase.trim();
    if (base.isEmpty) {
      return base;
    }

    final nomesExistentes = _gravacoes
        .where((gravacao) => gravacao.id != ignorarId)
        .map((gravacao) => _commandService.normalize(gravacao.nome))
        .toSet();

    var candidato = base;
    var contador = 1;
    while (nomesExistentes.contains(_commandService.normalize(candidato))) {
      candidato = '$base$contador';
      contador++;
    }

    return candidato;
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
      debugPrint('Erro ao registrar histórico persistente: $e');
    }
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

            if (_erro != null) {
              return ListView(
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
                    onPressed: _carregarGravacoes,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (_gravacoes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_gravacaoPendenteExclusao != null) ...[
                    _ConfirmacaoExclusaoCard(
                      gravacao: _gravacaoPendenteExclusao!,
                      onConfirmar: () {
                        unawaited(_handleConfirmarExclusaoPendente());
                      },
                      onCancelar: () {
                        voiceSetState(() {
                          _gravacaoPendenteExclusao = null;
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
                  _gravacoes.length +
                  (_gravacaoPendenteExclusao != null ? 1 : 0),
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (_gravacaoPendenteExclusao != null && index == 0) {
                  return _ConfirmacaoExclusaoCard(
                    gravacao: _gravacaoPendenteExclusao!,
                    onConfirmar: () {
                      unawaited(_handleConfirmarExclusaoPendente());
                    },
                    onCancelar: () {
                      voiceSetState(() {
                        _gravacaoPendenteExclusao = null;
                        voiceStatusMessage = 'Exclusao cancelada.';
                      });
                    },
                  );
                }

                final gravacaoIndex = _gravacaoPendenteExclusao != null
                    ? index - 1
                    : index;
                final gravacao = _gravacoes[gravacaoIndex];
                final reproduzindo = _gravacaoReproduzindoId == gravacao.id;

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
                        color: Colors.deepPurple,
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
