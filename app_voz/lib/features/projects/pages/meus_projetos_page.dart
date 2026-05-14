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
  final List<Projeto> _projetos = [];
  bool _carregando = true;
  bool _ouvindo = false;
  bool _escutaContinuaAtiva = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  String? _erro;
  String? _statusVoz;
  String? _nomeProjetoVoz;
  String? _descricaoProjetoVoz;
  bool _abriuCriacaoInicial = false;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.abrirCriacaoAoEntrar && !_abriuCriacaoInicial && mounted) {
        _abriuCriacaoInicial = true;
        _abrirCriacaoProjeto();
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

  Future<void> _abrirCriacaoProjeto() async {
    await _suspenderEscutaParaAcao();

    if (!mounted) {
      return;
    }

    final resultado = await showDialog<Projeto>(
      context: context,
      builder: (dialogContext) {
        return _CriarProjetoDialog(
          usuario: widget.usuario,
          nomeInicial: _nomeProjetoVoz,
          descricaoInicial: _descricaoProjetoVoz,
        );
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
        builder: (_) =>
            ProjetoDetalhesPage(usuario: widget.usuario, projeto: resultado),
      ),
    );

    if (mounted) {
      await _carregarProjetos();
    }
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
        await _criarProjetoPorVozOuAbrirFormulario();
        return;
      case VoiceCommandType.definirNomeProjeto:
        setState(() {
          _nomeProjetoVoz = resultado.parametro;
          _statusVoz = 'Nome do projeto definido: ${resultado.parametro}.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.definirDescricaoProjeto:
        setState(() {
          _descricaoProjetoVoz = resultado.parametro;
          _statusVoz = 'Descricao do projeto definida por voz.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.abrirProjetoPorNome:
        await _abrirProjetoPorNome(resultado.parametro);
        _executandoComandoVoz = false;
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

    Future.delayed(const Duration(milliseconds: 700), () {
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

  Future<void> _suspenderEscutaParaAcao() async {
    _paradaManualEscuta = true;
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

  Future<void> _criarProjetoPorVozOuAbrirFormulario() async {
    final nome = _nomeProjetoVoz?.trim();

    if (nome == null || nome.isEmpty) {
      await _abrirCriacaoProjeto();
      _executandoComandoVoz = false;
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

    final descricao = _descricaoProjetoVoz?.trim();
    final novoProjeto = Projeto(
      usuarioId: usuarioId,
      nome: nome,
      descricao: descricao == null || descricao.isEmpty ? null : descricao,
      dataCriacao: DateTime.now().toIso8601String(),
    );

    final id = await ProjetoRepository.instance.criarProjeto(novoProjeto);

    if (!mounted) {
      return;
    }

    _nomeProjetoVoz = null;
    _descricaoProjetoVoz = null;
    await _carregarProjetos();

    if (!mounted) {
      return;
    }

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
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final projeto = _projetos[index];

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.12,
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

class _CriarProjetoDialog extends StatefulWidget {
  final Usuario usuario;
  final String? nomeInicial;
  final String? descricaoInicial;

  const _CriarProjetoDialog({
    required this.usuario,
    this.nomeInicial,
    this.descricaoInicial,
  });

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
    _nomeController = TextEditingController(text: widget.nomeInicial);
    _descricaoController = TextEditingController(text: widget.descricaoInicial);
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
