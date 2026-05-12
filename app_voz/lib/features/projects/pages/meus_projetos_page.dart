import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/projeto_repository.dart';
import 'projeto_detalhes_page.dart';

class MeusProjetosPage extends StatefulWidget {
  final Usuario usuario;
  final bool abrirCriacaoAoEntrar;

  const MeusProjetosPage({
    super.key,
    required this.usuario,
    this.abrirCriacaoAoEntrar = false,
  });

  @override
  State<MeusProjetosPage> createState() => _MeusProjetosPageState();
}

class _MeusProjetosPageState extends State<MeusProjetosPage> {
  final List<Projeto> _projetos = [];
  bool _carregando = true;
  String? _erro;
  bool _abriuCriacaoInicial = false;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.abrirCriacaoAoEntrar && !_abriuCriacaoInicial && mounted) {
        _abriuCriacaoInicial = true;
        _abrirCriacaoProjeto();
      }
    });
  }

  Future<void> _carregarProjetos() async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Usuário sem identificação para buscar projetos.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final projetos = await ProjetoRepository.instance
          .listarProjetosPorUsuario(usuarioId);

      if (!mounted) {
        return;
      }

      setState(() {
        _projetos
          ..clear()
          ..addAll(projetos);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar projetos: $e';
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
    return '$dia/$mes/$ano';
  }

  Future<void> _abrirCriacaoProjeto() async {
    final resultado = await showDialog<Projeto>(
      context: context,
      builder: (dialogContext) {
        return _CriarProjetoDialog(usuario: widget.usuario);
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    await _carregarProjetos();

    if (!mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjetoDetalhesPage(
          usuario: widget.usuario,
          projeto: resultado,
        ),
      ),
    );

    if (mounted) {
      await _carregarProjetos();
    }
  }

  Future<void> _abrirProjeto(Projeto projeto) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjetoDetalhesPage(
          usuario: widget.usuario,
          projeto: projeto,
        ),
      ),
    );

    if (mounted) {
      await _carregarProjetos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Projetos'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCriacaoProjeto,
        icon: const Icon(Icons.add),
        label: const Text('Novo projeto'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarProjetos,
        child: Builder(
          builder: (context) {
            if (_carregando) {
              return const AppLoadingView(
                message: 'Carregando seus projetos...',
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
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _carregarProjetos,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (_projetos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.folder_open_outlined,
                    title: 'Nenhum projeto criado ainda',
                    subtitle:
                        'Crie um projeto para começar a organizar suas gravações.',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _projetos.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final projeto = _projetos[index];

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                      child: Icon(
                        Icons.folder_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      projeto.nome,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (projeto.descricao != null &&
                              projeto.descricao!.isNotEmpty)
                            Text(projeto.descricao!),
                          const SizedBox(height: 4),
                          Text('Criado em: ${_formatarData(projeto.dataCriacao)}'),
                        ],
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    onTap: () => _abrirProjeto(projeto),
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

class _CriarProjetoDialog extends StatefulWidget {
  final Usuario usuario;

  const _CriarProjetoDialog({required this.usuario});

  @override
  State<_CriarProjetoDialog> createState() => _CriarProjetoDialogState();
}

class _CriarProjetoDialogState extends State<_CriarProjetoDialog> {
  late final TextEditingController _nomeController;
  late final TextEditingController _descricaoController;
  late final FocusNode _nomeFocusNode;
  late final FocusNode _descricaoFocusNode;

  bool _salvando = false;
  String? _erroLocal;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController();
    _descricaoController = TextEditingController();
    _nomeFocusNode = FocusNode();
    _descricaoFocusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nomeFocusNode.requestFocus();
      }
    });
  }

  Future<void> _salvar() async {
    final usuarioId = widget.usuario.id;
    final nome = _nomeController.text.trim();
    final descricao = _descricaoController.text.trim();

    if (usuarioId == null) {
      setState(() {
        _erroLocal = 'Usuário inválido para criar projeto.';
      });
      return;
    }

    if (nome.isEmpty) {
      setState(() {
        _erroLocal = 'Informe o nome do projeto.';
      });
      _nomeFocusNode.requestFocus();
      return;
    }

    setState(() {
      _salvando = true;
      _erroLocal = null;
    });

    try {
      final novoProjeto = Projeto(
        usuarioId: usuarioId,
        nome: nome,
        descricao: descricao.isEmpty ? null : descricao,
        dataCriacao: DateTime.now().toIso8601String(),
      );

      final id = await ProjetoRepository.instance.criarProjeto(novoProjeto);

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        Projeto(
          id: id,
          usuarioId: novoProjeto.usuarioId,
          nome: novoProjeto.nome,
          descricao: novoProjeto.descricao,
          dataCriacao: novoProjeto.dataCriacao,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
        _erroLocal = 'Erro ao salvar projeto: $e';
      });
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _nomeFocusNode.dispose();
    _descricaoFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo projeto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nomeController,
              focusNode: _nomeFocusNode,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _descricaoFocusNode.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Nome do projeto',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descricaoController,
              focusNode: _descricaoFocusNode,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _salvar(),
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
              ),
            ),
            if (_erroLocal != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _erroLocal!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _salvando ? null : _salvar,
          child: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Criar'),
        ),
      ],
    );
  }
}
