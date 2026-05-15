import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/comando_voz.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../../repositories/projeto_repository.dart';
import '../../voices/controllers/voice_command_controller.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/speech_service.dart';
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
  final SpeechService _speechService = SpeechService();
  final VoiceCommandController _commandController = VoiceCommandController();
  final CommandService _commandService = const CommandService();
  final TextEditingController _nomeProjetoController = TextEditingController();
  final TextEditingController _descricaoProjetoController =
      TextEditingController();
  final List<Projeto> _projetos = [];
  bool _carregando = true;
  bool _ouvindo = false;
  bool _escutaContinuaAtiva = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  bool _criacaoProjetoAtiva = false;
  bool _salvandoProjeto = false;
  String? _erro;
  String? _statusVoz;
  bool _abriuCriacaoInicial = false;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.abrirCriacaoAoEntrar && !_abriuCriacaoInicial && mounted) {
        _abriuCriacaoInicial = true;
        _mostrarCriacaoProjeto(limpar: true);
        _iniciarEscutaContinuaSeAtiva();
        return;
      }
      _iniciarEscutaContinuaSeAtiva();
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

  void _mostrarCriacaoProjeto({bool limpar = false}) {
    if (limpar) {
      _nomeProjetoController.clear();
      _descricaoProjetoController.clear();
    }

    setState(() {
      _criacaoProjetoAtiva = true;
      _statusVoz = 'Novo projeto aberto. Diga o nome e a descricao.';
    });
  }

  Future<void> _alternarEscutaVoz() async {
    if (_ouvindo) {
      _paradaManualEscuta = true;
      await _speechService.stopListening();

      if (!mounted) {
        return;
      }

      setState(() {
        _ouvindo = false;
        _statusVoz = 'Escuta encerrada.';
      });
      return;
    }

    _paradaManualEscuta = false;
    await _iniciarEscutaVoz();
  }

  Future<void> _iniciarEscutaContinuaSeAtiva() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    _escutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;

    if (_escutaContinuaAtiva && !_ouvindo && !_paradaManualEscuta) {
      await _iniciarEscutaVoz();
    }
  }

  Future<void> _iniciarEscutaVoz() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    _escutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;

    if (!configuracao.comandosVozAtivos) {
      setState(() {
        _statusVoz = 'Comandos de voz desativados.';
      });
      return;
    }

    setState(() {
      _ouvindo = true;
      _statusVoz = 'Ouvindo comando de projeto...';
    });

    await _speechService.startListening(
      onResult: (texto) {
        unawaited(_executarComandoVoz(texto));
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }

        if (status == 'done' || status == 'notListening') {
          setState(() {
            _ouvindo = false;
          });
          _reiniciarEscutaContinuaSeNecessario();
        }
      },
      onError: (error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ouvindo = false;
          _statusVoz = 'Erro no reconhecimento de voz: $error';
        });
        _reiniciarEscutaContinuaSeNecessario();
      },
    );
  }

  Future<void> _executarComandoVoz(String texto) async {
    if (_executandoComandoVoz) {
      return;
    }

    _executandoComandoVoz = true;
    final resultadoController = await _commandController.interpret(texto);
    final resultado = resultadoController.commandResult;

    unawaited(_registrarComando(resultado));

    if (!mounted || resultado.normalizedText.isEmpty) {
      _executandoComandoVoz = false;
      return;
    }

    switch (resultado.type) {
      case VoiceCommandType.abrirNovoProjeto:
        _mostrarCriacaoProjeto(limpar: true);
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.criarProjeto:
        await _criarProjetoPorVoz();
        return;
      case VoiceCommandType.cancelarProjeto:
        _cancelarCriacaoProjeto();
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.substituirNomeProjeto:
        setState(() {
          _criacaoProjetoAtiva = true;
          _nomeProjetoController.text = resultado.parametro ?? '';
          _statusVoz = 'Nome do projeto definido: ${resultado.parametro}.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
        setState(() {
          _criacaoProjetoAtiva = true;
          _descricaoProjetoController.text = resultado.parametro ?? '';
          _statusVoz = 'Descricao do projeto definida por voz.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.abrirProjetoPorNome:
        await _abrirProjetoPorNome(resultado.parametro);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.renomearProjeto:
        await _renomearProjetoPorVoz(
          resultado.parametro,
          resultado.parametroSecundario,
        );
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.voltar:
        await _suspenderEscutaParaAcao();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        Navigator.maybePop(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.confirmarAcao:
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.ativarControleVoz:
      case VoiceCommandType.desativarControleVoz:
      case VoiceCommandType.ativarEscutaContinua:
      case VoiceCommandType.desativarEscutaContinua:
      case VoiceCommandType.ativarFeedbackSonoro:
      case VoiceCommandType.desativarFeedbackSonoro:
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        setState(() {
          _statusVoz = resultado.recognized
              ? 'Comando nao disponivel nesta tela.'
              : 'Comando nao reconhecido nesta tela.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
    }
  }

  void _reiniciarEscutaContinuaSeNecessario() {
    if (!_escutaContinuaAtiva ||
        _paradaManualEscuta ||
        _executandoComandoVoz ||
        !mounted) {
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted ||
          _ouvindo ||
          _paradaManualEscuta ||
          _executandoComandoVoz ||
          !_escutaContinuaAtiva) {
        return;
      }

      unawaited(_iniciarEscutaVoz());
    });
  }

  Future<void> _suspenderEscutaParaAcao({bool manterPausada = false}) async {
    _paradaManualEscuta = manterPausada;
    _escutaContinuaAtiva = false;

    if (_ouvindo || _speechService.isListening) {
      await _speechService.cancelListening();
    }

    if (mounted) {
      setState(() {
        _ouvindo = false;
      });
    }
  }

  Future<void> _retomarEscutaContinuaAposAcao() async {
    if (!mounted || _paradaManualEscuta) {
      return;
    }

    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    _escutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;
    if (_escutaContinuaAtiva && !_ouvindo) {
      await _iniciarEscutaVoz();
    }
  }

  void _cancelarCriacaoProjeto() {
    setState(() {
      _nomeProjetoController.clear();
      _descricaoProjetoController.clear();
      _criacaoProjetoAtiva = false;
      _statusVoz = 'Criacao de projeto cancelada.';
    });
  }

  Future<void> _criarProjetoPorVoz() async {
    final nome = _nomeProjetoController.text.trim();

    if (nome.isEmpty) {
      _mostrarCriacaoProjeto();
      setState(() {
        _statusVoz = 'Informe o nome do projeto antes de criar.';
      });
      _executandoComandoVoz = false;
      _reiniciarEscutaContinuaSeNecessario();
      return;
    }

    final usuarioId = widget.usuario.id;
    if (usuarioId == null) {
      setState(() {
        _statusVoz = 'Usuario sem identificacao para criar projeto.';
      });
      _executandoComandoVoz = false;
      return;
    }

    setState(() {
      _salvandoProjeto = true;
      _statusVoz = 'Criando projeto...';
    });

    final descricao = _descricaoProjetoController.text.trim();
    final nomeFinal = _gerarNomeProjetoUnico(nome);
    final novoProjeto = Projeto(
      usuarioId: usuarioId,
      nome: nomeFinal,
      descricao: descricao.isEmpty ? null : descricao,
      dataCriacao: DateTime.now().toIso8601String(),
    );

    final id = await ProjetoRepository.instance.criarProjeto(novoProjeto);

    if (!mounted) {
      return;
    }

    _nomeProjetoController.clear();
    _descricaoProjetoController.clear();
    _salvandoProjeto = false;
    _criacaoProjetoAtiva = false;
    await _carregarProjetos();

    if (!mounted) {
      return;
    }

    await _suspenderEscutaParaAcao();
    await _abrirProjeto(
      Projeto(
        id: id,
        usuarioId: novoProjeto.usuarioId,
        nome: novoProjeto.nome,
        descricao: novoProjeto.descricao,
        dataCriacao: novoProjeto.dataCriacao,
      ),
    );
    _executandoComandoVoz = false;
    await _retomarEscutaContinuaAposAcao();
  }

  Future<void> _abrirProjetoPorNome(String? nomeFalado) async {
    final nomeNormalizado = _commandService.normalize(nomeFalado ?? '');
    if (nomeNormalizado.isEmpty) {
      setState(() {
        _statusVoz = 'Diga o nome do projeto que deseja abrir.';
      });
      _executandoComandoVoz = false;
      return;
    }

    Projeto? projeto;
    for (final item in _projetos) {
      if (_commandService.normalize(item.nome).contains(nomeNormalizado)) {
        projeto = item;
        break;
      }
    }

    if (projeto == null) {
      setState(() {
        _statusVoz = 'Projeto "$nomeFalado" nao encontrado.';
      });
      _executandoComandoVoz = false;
      return;
    }

    await _suspenderEscutaParaAcao();
    await _abrirProjeto(projeto);
    await _retomarEscutaContinuaAposAcao();
  }

  Future<void> _renomearProjetoPorVoz(
    String? nomeAtual,
    String? novoNome,
  ) async {
    final projeto = _buscarProjetoPorNome(nomeAtual);

    if (projeto == null || novoNome == null || novoNome.trim().isEmpty) {
      setState(() {
        _statusVoz = 'Diga: renomear projeto nome atual para novo nome.';
      });
      return;
    }

    await _salvarNovoNomeProjeto(projeto, novoNome.trim());
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

  Future<void> _salvarNovoNomeProjeto(Projeto projeto, String novoNome) async {
    if (projeto.id == null) {
      return;
    }

    final nomeFinal = _gerarNomeProjetoUnico(novoNome, ignorarId: projeto.id);
    final projetoAtualizado = Projeto(
      id: projeto.id,
      usuarioId: projeto.usuarioId,
      nome: nomeFinal,
      descricao: projeto.descricao,
      dataCriacao: projeto.dataCriacao,
    );

    await ProjetoRepository.instance.atualizarProjeto(projetoAtualizado);

    if (!mounted) {
      return;
    }

    setState(() {
      final index = _projetos.indexWhere((item) => item.id == projeto.id);
      if (index != -1) {
        _projetos[index] = projetoAtualizado;
      }
      _statusVoz = 'Projeto renomeado para $nomeFinal.';
    });
  }

  Projeto? _buscarProjetoPorNome(String? nome) {
    final nomeNormalizado = _commandService.normalize(nome ?? '');
    if (nomeNormalizado.isEmpty) {
      return null;
    }

    for (final projeto in _projetos) {
      if (_commandService.normalize(projeto.nome).contains(nomeNormalizado)) {
        return projeto;
      }
    }

    return null;
  }

  String _gerarNomeProjetoUnico(String nomeBase, {int? ignorarId}) {
    final base = nomeBase.trim();
    if (base.isEmpty) {
      return base;
    }

    final nomesExistentes = _projetos
        .where((projeto) => projeto.id != ignorarId)
        .map((projeto) => _commandService.normalize(projeto.nome))
        .toSet();

    var candidato = base;
    var contador = 1;
    while (nomesExistentes.contains(_commandService.normalize(candidato))) {
      candidato = '$base$contador';
      contador++;
    }

    return candidato;
  }

  Future<void> _registrarComando(CommandResult resultado) async {
    final usuarioId = widget.usuario.id;
    if (usuarioId == null || resultado.normalizedText.isEmpty) {
      return;
    }

    try {
      await ComandoVozRepository.instance.registrarComando(
        ComandoVoz(
          usuarioId: usuarioId,
          textoReconhecido: resultado.originalText,
          tipoComando: resultado.tipoComando,
          statusReconhecimento: resultado.statusReconhecimento,
          acaoExecutada: resultado.acaoExecutada,
          dataHora: DateTime.now().toIso8601String(),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao registrar comando de voz: $e');
    }
  }

  Future<void> _abrirProjeto(Projeto projeto) async {
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

  @override
  void dispose() {
    _speechService.stopListening();
    _nomeProjetoController.dispose();
    _descricaoProjetoController.dispose();
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
            tooltip: _ouvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: _alternarEscutaVoz,
            icon: Icon(_ouvindo ? Icons.mic : Icons.mic_none),
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
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_criacaoProjetoAtiva) ...[
                    _ProjetoCriacaoCard(
                      nomeController: _nomeProjetoController,
                      descricaoController: _descricaoProjetoController,
                      salvando: _salvandoProjeto,
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
              itemCount: _projetos.length + (_criacaoProjetoAtiva ? 1 : 0),
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (_criacaoProjetoAtiva && index == 0) {
                  return _ProjetoCriacaoCard(
                    nomeController: _nomeProjetoController,
                    descricaoController: _descricaoProjetoController,
                    salvando: _salvandoProjeto,
                    onCriar: _criarProjetoPorVoz,
                    onCancelar: _cancelarCriacaoProjeto,
                  );
                }

                final projetoIndex = _criacaoProjetoAtiva ? index - 1 : index;
                final projeto = _projetos[projetoIndex];

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
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'open') {
                          _abrirProjeto(projeto);
                        }
                        if (value == 'rename') {
                          _renomearProjetoManual(projeto);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'open', child: Text('Abrir')),
                        PopupMenuItem(value: 'rename', child: Text('Renomear')),
                      ],
                    ),
                    onTap: () => _abrirProjeto(projeto),
                    onLongPress: () => _renomearProjetoManual(projeto),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: _statusVoz == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  _statusVoz!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
    );
  }
}

class _ProjetoCriacaoCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Novo projeto', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: nomeController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nome do projeto'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: descricaoController,
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
                    onPressed: salvando ? null : onCancelar,
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: salvando ? null : onCriar,
                    child: salvando
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renomear projeto'),
      content: TextField(
        controller: _controller,
        autofocus: true,
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
              decoration: const InputDecoration(labelText: 'Nome do projeto'),
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
              Text(_erroLocal!, style: const TextStyle(color: Colors.red)),
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
