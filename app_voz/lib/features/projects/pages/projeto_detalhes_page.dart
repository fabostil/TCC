import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/gravacao_repository.dart';
import '../../editor/pages/editor_page.dart';
import '../../editor/services/audio_player_service.dart';

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

class _ProjetoDetalhesPageState extends State<ProjetoDetalhesPage> {
  final List<Gravacao> _gravacoes = [];
  final AudioPlayerService _playerService = AudioPlayerService();

  bool _carregando = true;
  String? _erro;
  int? _gravacaoReproduzindoId;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _carregarGravacoes() async {
    final projetoId = widget.projeto.id;

    if (projetoId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Projeto sem identificação para buscar gravações.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final gravacoes = await GravacaoRepository.instance
          .listarGravacoesPorProjeto(projetoId);

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
        _erro = 'Erro ao carregar gravações do projeto: $e';
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

  int get _duracaoTotalSegundos =>
      _gravacoes.fold(0, (total, item) => total + item.duracaoSegundos);

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

    final gravacaoAtualizada = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      projetoId: gravacao.projetoId,
      nome: novoNome,
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível renomear a gravação: $e')),
      );
    }
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

      AppFeedback.showMessage(
        context,
        'Gravação removida deste projeto com sucesso.',
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

  Future<void> _abrirEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorPage(
          usuario: widget.usuario,
          projeto: widget.projeto,
        ),
      ),
    );

    if (mounted) {
      await _carregarGravacoes();
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _playerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projeto.nome),
        centerTitle: true,
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
            if (_carregando) {
              return const AppLoadingView(
                message: 'Carregando detalhes do projeto...',
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

            return ListView(
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
                                valor: _gravacoes.length.toString(),
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
                if (_gravacoes.isEmpty)
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
                if (_gravacoes.isNotEmpty)
                  ..._gravacoes.map(
                    (gravacao) {
                      final reproduzindo =
                          _gravacaoReproduzindoId == gravacao.id;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: IconButton(
                              onPressed: () => _alternarReproducao(gravacao),
                              icon: Icon(
                                reproduzindo
                                    ? Icons.stop_circle
                                    : Icons.play_circle,
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
                                  Text(
                                    'Data: ${_formatarData(gravacao.dataCriacao)}',
                                  ),
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
                              },
                              itemBuilder: (context) => const [
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
                    },
                  ),
              ],
            );
          },
        ),
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
        color: Colors.deepPurple.withOpacity(0.08),
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
