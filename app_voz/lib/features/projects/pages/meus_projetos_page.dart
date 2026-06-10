import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_search_field.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/services/command_service.dart';
import '../../editor/pages/editor_page.dart';
import '../controllers/projects_list_controller.dart';
import 'projeto_detalhes_page.dart';

const int _minProjectNameLength = 2;
const int _maxProjectNameLength = 80;

String? _validateProjectName(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Informe o nome do projeto.';
  }
  if (trimmed.length < _minProjectNameLength) {
    return 'O nome deve ter pelo menos 2 caracteres.';
  }
  if (trimmed.length > _maxProjectNameLength) {
    return 'O nome deve ter no máximo 80 caracteres.';
  }
  return null;
}

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

class _MeusProjetosPageState extends State<MeusProjetosPage>
    with ContextualVoiceListeningMixin<MeusProjetosPage> {
  final ProjectsListController _projectsController = ProjectsListController();
  final TextEditingController _nomeProjetoController = TextEditingController();
  final TextEditingController _descricaoProjetoController =
      TextEditingController();
  final TextEditingController _buscaController = TextEditingController();
  Timer? _buscaDebounce;
  bool _abriuCriacaoInicial = false;
  Projeto? _projetoPendenteExclusao;
  Projeto? _projetoContextualSelecionado;
  int? _renomeandoProjetoId;
  int? _excluindoProjetoId;

  ProjectsListState get _projectsState => _projectsController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.meusProjetos;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando de projeto...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  void initState() {
    super.initState();
    _projectsController.addListener(_onProjectsStateChanged);
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchContextualVoice,
    );
    _carregarProjetos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.abrirCriacaoAoEntrar && !_abriuCriacaoInicial && mounted) {
        _abriuCriacaoInicial = true;
        _mostrarCriacaoProjeto(limpar: true);
      }
      scheduleVoiceListeningOnFirstFrame();
    });
  }

  void _onProjectsStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarProjetos() {
    return _projectsController.load(
      usuarioId: widget.usuario.id,
      searchTerm: _buscaController.text,
    );
  }

  void _onBuscaAlterada(String termo) {
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _carregarProjetos();
      }
    });
  }

  void _limparBusca() {
    if (_buscaController.text.isEmpty) {
      return;
    }

    _buscaDebounce?.cancel();
    _buscaController.clear();
    _carregarProjetos();
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

  void _mostrarCriacaoProjeto({bool limpar = false}) {
    if (limpar) {
      _nomeProjetoController.clear();
      _descricaoProjetoController.clear();
    }

    voiceSetState(() {
      _projectsController.showCreation();
      voiceStatusMessage = 'Novo projeto aberto. Diga o nome e a descricao.';
    });
  }

  Future<VoiceCommandPageResult> _dispatchContextualVoice(
    CommandResult resultado,
  ) async {
    switch (resultado.type) {
      case VoiceCommandType.abrirNovoProjeto:
        _mostrarCriacaoProjeto(limpar: true);
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.criarProjeto:
        return _criarProjetoPorVoz();
      case VoiceCommandType.cancelarProjeto:
        _cancelarCriacaoProjeto();
        return VoiceCommandPageResult.handled(
          message: 'Criacao de projeto cancelada.',
        );
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.substituirNomeProjeto:
        voiceSetState(() {
          _projectsController.showCreation();
          _nomeProjetoController.text = resultado.parametro ?? '';
          voiceStatusMessage =
              'Nome do projeto definido: ${resultado.parametro}.';
        });
        return VoiceCommandPageResult.handled(
          message: 'Nome do projeto definido: ${resultado.parametro}.',
        );
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
        voiceSetState(() {
          _projectsController.showCreation();
          _descricaoProjetoController.text = resultado.parametro ?? '';
          voiceStatusMessage = 'Descricao do projeto definida por voz.';
        });
        return VoiceCommandPageResult.handled(
          message: 'Descricao do projeto definida por voz.',
        );
      case VoiceCommandType.abrirProjetoPorNome:
        return _abrirProjetoPorNome(resultado.parametro);
      case VoiceCommandType.buscarProjetos:
        return _buscarProjetosPorVoz(resultado.parametro);
      case VoiceCommandType.limparBusca:
        _limparBusca();
        return VoiceCommandPageResult.handled(message: 'Busca limpa.');
      case VoiceCommandType.renomearProjeto:
        return _renomearProjetoPorVoz(
          resultado.parametro,
          resultado.parametroSecundario,
        );
      case VoiceCommandType.excluirProjeto:
        return _excluirProjetoPorVoz(resultado.parametro);
      case VoiceCommandType.confirmarAcao:
        return _confirmarExclusaoProjetoPorVoz();
      case VoiceCommandType.cancelarAcao:
        return _cancelarExclusaoProjetoPorVoz();
      case VoiceCommandType.voltar:
        await suspendContextualVoiceListening();
        if (mounted) {
          Navigator.maybePop(context);
        }
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.abrirEditor:
        return _abrirEditorPorVoz();
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.buscarGravacoes:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
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
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        return VoiceCommandPageResult.unavailable(
          recognized: resultado.recognized,
        );
    }
  }

  Future<VoiceCommandPageResult> _buscarProjetosPorVoz(String? termo) async {
    final termoBusca = termo?.trim() ?? '';
    if (termoBusca.isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga o termo para buscar nos projetos.',
      );
    }

    _buscaDebounce?.cancel();
    _buscaController.text = termoBusca;
    await _carregarProjetos();
    return VoiceCommandPageResult.handled(
      message: 'Busca por $termoBusca aplicada nos projetos.',
    );
  }

  void _cancelarCriacaoProjeto() {
    voiceSetState(() {
      _nomeProjetoController.clear();
      _descricaoProjetoController.clear();
      _projectsController.cancelCreation();
      voiceStatusMessage = 'Criacao de projeto cancelada.';
    });
  }

  Future<VoiceCommandPageResult> _criarProjetoPorVoz() async {
    final nome = _nomeProjetoController.text.trim();

    if (nome.isEmpty) {
      _mostrarCriacaoProjeto();
      return VoiceCommandPageResult.handled(
        message: 'Informe o nome do projeto antes de criar.',
      );
    }

    final usuarioId = widget.usuario.id;
    if (usuarioId == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem identificacao para criar projeto.',
      );
    }

    voiceSetState(() {
      voiceStatusMessage = 'Criando projeto...';
    });

    final novoProjeto = await _projectsController.createProject(
      usuarioId: usuarioId,
      name: nome,
      description: _descricaoProjetoController.text,
    );

    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    _nomeProjetoController.clear();
    _descricaoProjetoController.clear();

    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await suspendContextualVoiceListening();
    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _abrirProjeto(novoProjeto);
    await startContinuousVoiceListeningIfActive();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _abrirProjetoPorNome(
    String? nomeFalado,
  ) async {
    if ((nomeFalado ?? '').trim().isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga o nome do projeto que deseja abrir.',
      );
    }

    final projeto = _projectsController.findByName(nomeFalado);

    if (projeto == null) {
      return VoiceCommandPageResult.handled(
        message: 'Projeto "$nomeFalado" nao encontrado.',
      );
    }

    await suspendContextualVoiceListening();
    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _abrirProjeto(projeto);
    await startContinuousVoiceListeningIfActive();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _renomearProjetoPorVoz(
    String? nomeAtual,
    String? novoNome,
  ) async {
    final projeto = _buscarProjetoPorNome(nomeAtual);

    if (projeto == null || novoNome == null || novoNome.trim().isEmpty) {
      return VoiceCommandPageResult.handled(
        message: 'Diga: renomear projeto nome atual para novo nome.',
      );
    }

    await _salvarNovoNomeProjeto(projeto, novoNome.trim());
    return VoiceCommandPageResult.handled();
  }

  Future<void> _renomearProjetoManual(Projeto projeto) async {
    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) => _RenomearProjetoDialog(nomeInicial: projeto.nome),
    );

    if (novoNome == null || novoNome.trim().isEmpty) {
      return;
    }

    await _salvarNovoNomeProjeto(projeto, novoNome.trim());
  }

  Future<VoiceCommandPageResult> _excluirProjetoPorVoz(String? nome) async {
    final projeto = _buscarProjetoPorNome(nome);

    if (projeto == null) {
      return VoiceCommandPageResult.handled(
        message: 'Diga: excluir projeto nome do projeto.',
      );
    }

    voiceSetState(() {
      _projetoPendenteExclusao = projeto;
      voiceStatusMessage =
          'Excluir projeto ${projeto.nome}? Diga confirmar exclusao ou cancelar exclusao.';
    });

    return VoiceCommandPageResult.handled(
      message:
          'Excluir projeto ${projeto.nome}? Diga confirmar exclusao ou cancelar exclusao.',
    );
  }

  Future<VoiceCommandPageResult> _confirmarExclusaoProjetoPorVoz() async {
    final projeto = _projetoPendenteExclusao;
    if (projeto == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nao ha projeto aguardando confirmacao de exclusao.',
      );
    }

    await _excluirProjeto(projeto, pedirConfirmacao: false);
    return VoiceCommandPageResult.handled(
      message: 'Projeto ${projeto.nome} excluido.',
    );
  }

  Future<VoiceCommandPageResult> _cancelarExclusaoProjetoPorVoz() async {
    if (_projetoPendenteExclusao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Nao ha exclusao de projeto pendente.',
      );
    }

    voiceSetState(() {
      _projetoPendenteExclusao = null;
      voiceStatusMessage = 'Exclusao de projeto cancelada.';
    });

    return VoiceCommandPageResult.handled(
      message: 'Exclusao de projeto cancelada.',
    );
  }

  Future<void> _excluirProjetoManual(Projeto projeto) async {
    await _excluirProjeto(projeto, pedirConfirmacao: true);
  }

  Future<void> _excluirProjeto(
    Projeto projeto, {
    required bool pedirConfirmacao,
  }) async {
    if (projeto.id == null) {
      return;
    }

    if (pedirConfirmacao) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Excluir projeto?'),
          content: Text(
            'O projeto "${projeto.nome}" sera removido. As gravacoes vinculadas continuam salvas em Minhas gravacoes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
          ],
        ),
      );

      if (confirmar != true) {
        return;
      }
    }

    setState(() {
      _excluindoProjetoId = projeto.id;
    });

    try {
      await _projectsController.deleteProject(project: projeto);

      if (!mounted) {
        return;
      }

      voiceSetState(() {
        _projetoPendenteExclusao = null;
        voiceStatusMessage = 'Projeto ${projeto.nome} excluido.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _excluindoProjetoId = null;
        });
      }
    }
  }

  Future<void> _salvarNovoNomeProjeto(Projeto projeto, String novoNome) async {
    if (projeto.id == null) {
      return;
    }

    setState(() {
      _renomeandoProjetoId = projeto.id;
    });

    try {
      final projetoAtualizado = await _projectsController.renameProject(
        project: projeto,
        newName: novoNome,
      );

      if (!mounted) {
        return;
      }
      voiceSetState(() {
        voiceStatusMessage =
            'Projeto renomeado para ${projetoAtualizado.nome}.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _renomeandoProjetoId = null;
        });
      }
    }
  }

  Projeto? _buscarProjetoPorNome(String? nome) {
    return _projectsController.findByName(nome);
  }

  void _selecionarProjetoContextual(Projeto projeto) {
    _projetoContextualSelecionado = projeto;
  }

  Future<VoiceCommandPageResult> _abrirEditorPorVoz() async {
    final projeto = _projetoContextualSelecionado;
    if (projeto == null) {
      return VoiceCommandPageResult.handled(
        message: 'Abra um projeto primeiro para acessar o editor.',
      );
    }

    await suspendContextualVoiceListening();
    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorPage(usuario: widget.usuario, projeto: projeto),
      ),
    );

    if (mounted) {
      await _carregarProjetos();
      if (!mounted) {
        return VoiceCommandPageResult.handled(restartListening: false);
      }

      await startContinuousVoiceListeningIfActive();
    }

    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<void> _abrirProjeto(Projeto projeto) async {
    _selecionarProjetoContextual(projeto);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProjetoDetalhesPage(usuario: widget.usuario, projeto: projeto),
      ),
    );

    if (mounted) {
      await _carregarProjetos();
    }
  }

  Widget _buildBuscaProjetos() {
    return AppSearchField(
      controller: _buscaController,
      hintText: 'Buscar por nome ou descricao',
      onChanged: _onBuscaAlterada,
      onClear: _limparBusca,
      enabled: !_projectsState.loading,
    );
  }

  Widget _buildExclusaoPendente() {
    final projeto = _projetoPendenteExclusao;
    if (projeto == null) {
      return const SizedBox.shrink();
    }
    final excluindo = _excluindoProjetoId == projeto.id;

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Excluir "${projeto.nome}"?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: excluindo
                  ? null
                  : () => _cancelarExclusaoProjetoPorVoz(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: excluindo
                  ? null
                  : () => _confirmarExclusaoProjetoPorVoz(),
              child: excluindo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _buscaDebounce?.cancel();
    _buscaController.dispose();
    _nomeProjetoController.dispose();
    _descricaoProjetoController.dispose();
    _projectsController.removeListener(_onProjectsStateChanged);
    _projectsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Projetos'),
        actions: [
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarCriacaoProjeto(limpar: true),
        icon: const Icon(Icons.add),
        label: const Text('Novo projeto'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarProjetos,
        child: Builder(
          builder: (context) {
            final projectsState = _projectsState;
            final projetos = projectsState.projects;
            final criacaoProjetoAtiva = projectsState.creationActive;

            if (projectsState.loading) {
              return const AppLoadingView(
                message: 'Carregando seus projetos...',
              );
            }

            if (projectsState.error != null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text(
                    projectsState.error!,
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

            if (projetos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildBuscaProjetos(),
                  if (_projetoPendenteExclusao != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _buildExclusaoPendente(),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (criacaoProjetoAtiva) ...[
                    _ProjetoCriacaoCard(
                      nomeController: _nomeProjetoController,
                      descricaoController: _descricaoProjetoController,
                      salvando: projectsState.saving,
                      onCriar: _criarProjetoPorVoz,
                      onCancelar: _cancelarCriacaoProjeto,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  const SizedBox(height: 80),
                  const AppEmptyState(
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
              itemCount: projetos.length + (criacaoProjetoAtiva ? 1 : 0) + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    children: [
                      _buildBuscaProjetos(),
                      if (_projetoPendenteExclusao != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildExclusaoPendente(),
                      ],
                    ],
                  );
                }

                if (criacaoProjetoAtiva && index == 1) {
                  return _ProjetoCriacaoCard(
                    nomeController: _nomeProjetoController,
                    descricaoController: _descricaoProjetoController,
                    salvando: projectsState.saving,
                    onCriar: _criarProjetoPorVoz,
                    onCancelar: _cancelarCriacaoProjeto,
                  );
                }

                final projetoIndex = index - (criacaoProjetoAtiva ? 2 : 1);
                final projeto = projetos[projetoIndex];
                final processandoProjeto =
                    _renomeandoProjetoId == projeto.id ||
                    _excluindoProjetoId == projeto.id;

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
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
                          Text(
                            'Criado em: ${_formatarData(projeto.dataCriacao)}',
                          ),
                        ],
                      ),
                    ),
                    trailing: processandoProjeto
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            tooltip:
                                'Abrir menu de acoes do projeto ${projeto.nome}',
                            onOpened: () =>
                                _selecionarProjetoContextual(projeto),
                            onSelected: (value) {
                              _selecionarProjetoContextual(projeto);
                              if (value == 'open') {
                                _abrirProjeto(projeto);
                              }
                              if (value == 'rename') {
                                _renomearProjetoManual(projeto);
                              }
                              if (value == 'delete') {
                                _excluirProjetoManual(projeto);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'open',
                                child: Text('Abrir'),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Renomear'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                    onTap: processandoProjeto
                        ? null
                        : () => _abrirProjeto(projeto),
                    onLongPress: () {
                      _selecionarProjetoContextual(projeto);
                      _renomearProjetoManual(projeto);
                    },
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

class _ProjetoCriacaoCard extends StatefulWidget {
  final TextEditingController nomeController;
  final TextEditingController descricaoController;
  final bool salvando;
  final VoidCallback onCriar;
  final VoidCallback onCancelar;

  const _ProjetoCriacaoCard({
    required this.nomeController,
    required this.descricaoController,
    required this.salvando,
    required this.onCriar,
    required this.onCancelar,
  });

  @override
  State<_ProjetoCriacaoCard> createState() => _ProjetoCriacaoCardState();
}

class _ProjetoCriacaoCardState extends State<_ProjetoCriacaoCard> {
  final _formKey = GlobalKey<FormState>();

  void _criarProjeto() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    widget.onCriar();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Novo projeto',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: widget.nomeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nome do projeto'),
                validator: _validateProjectName,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: widget.descricaoController,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Descricao (opcional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.salvando ? null : widget.onCancelar,
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.salvando ? null : _criarProjeto,
                      child: widget.salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Criar projeto'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenomearProjetoDialog extends StatefulWidget {
  final String nomeInicial;

  const _RenomearProjetoDialog({required this.nomeInicial});

  @override
  State<_RenomearProjetoDialog> createState() => _RenomearProjetoDialogState();
}

class _RenomearProjetoDialogState extends State<_RenomearProjetoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.nomeInicial);
  }

  @override
  void dispose() {
    _controller.dispose();
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
      title: const Text('Renomear projeto'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _salvar(),
          decoration: const InputDecoration(labelText: 'Novo nome'),
          validator: _validateProjectName,
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
