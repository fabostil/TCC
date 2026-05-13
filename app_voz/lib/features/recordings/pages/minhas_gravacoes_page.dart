import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
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
      nome: novoNome,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
      motivoParada: gravacao.motivoParada,
      maiorPico: gravacao.maiorPico,
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
    }
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas Gravações'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _carregarGravacoes,
        child: Builder(
          builder: (context) {
            if (_carregando) {
              return const AppLoadingView(message: 'Carregando suas gravações...');
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
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
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
              itemCount: _gravacoes.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final gravacao = _gravacoes[index];
                final reproduzindo = _gravacaoReproduzindoId == gravacao.id;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
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
                          Text('Duração: ${_formatarDuracao(gravacao.duracaoSegundos)}'),
                          if (gravacao.motivoParada != null) ...[
                            const SizedBox(height: 4),
                            Text('Parada: ${gravacao.motivoParada}'),
                          ],
                          const SizedBox(height: 4),
                          Text('Maior pico: ${gravacao.maiorPico.toStringAsFixed(1)} dB'),
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
