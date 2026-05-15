import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/comando_voz.dart';
import '../../../models/historico_acao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../../repositories/historico_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../voices/controllers/voice_command_controller.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/speech_service.dart';

class HistoricoPage extends StatefulWidget {
  final Usuario usuario;

  const HistoricoPage({super.key, required this.usuario});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  final SpeechService _speechService = SpeechService();
  final VoiceCommandController _commandController = VoiceCommandController();
  final List<HistoricoAcao> _eventos = [];

  bool _carregando = true;
  bool _ouvindo = false;
  bool _escutaContinuaAtiva = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  String? _erro;
  String? _statusVoz;
  String? _tipoSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarEscutaContinuaSeAtiva();
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
      _statusVoz = 'Ouvindo comando do historico...';
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
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _ouvindo = false;
          _statusVoz = 'Nao entendi. Pode repetir.';
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
      case VoiceCommandType.voltar:
        await _suspenderEscutaParaAcao();
        if (mounted) {
          Navigator.maybePop(context);
        }
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirDashboard:
        await _suspenderEscutaParaAcao();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardPage(usuario: widget.usuario),
          ),
        );
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirHistorico:
        setState(() {
          _statusVoz = 'Historico ja esta aberto.';
        });
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      default:
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

  @override
  void dispose() {
    _speechService.stopListening();
    super.dispose();
  }

  Future<void> _carregarHistorico() async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Usuario sem identificacao para carregar o historico.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final eventos = await HistoricoRepository.instance.listarPorUsuario(
        usuarioId,
        limite: 200,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _eventos
          ..clear()
          ..addAll(eventos);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Nao foi possivel carregar o historico: $e';
      });
    }
  }

  List<HistoricoAcao> get _eventosFiltrados {
    final tipo = _tipoSelecionado;

    if (tipo == null) {
      return _eventos;
    }

    return _eventos.where((evento) => evento.tipo == tipo).toList();
  }

  List<String> get _tiposDisponiveis {
    final tipos = _eventos.map((evento) => evento.tipo).toSet().toList()
      ..sort();

    return tipos;
  }

  String _formatarData(String dataIso) {
    final data = DateTime.tryParse(dataIso);

    if (data == null) {
      return 'Data invalida';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano $hora:$minuto';
  }

  String _formatarTipo(String tipo) {
    return tipo.replaceAll('_', ' ');
  }

  IconData _iconePorTipo(String tipo) {
    if (tipo.contains('gravacao')) {
      return Icons.mic_none_rounded;
    }

    if (tipo.contains('reproducao')) {
      return Icons.play_circle_outline_rounded;
    }

    if (tipo.contains('comando')) {
      return Icons.record_voice_over_outlined;
    }

    if (tipo.contains('marcador')) {
      return Icons.bookmark_border_rounded;
    }

    if (tipo.contains('texto')) {
      return Icons.notes_rounded;
    }

    return Icons.history_rounded;
  }

  Color _corPorTipo(BuildContext context, String tipo) {
    final colorScheme = Theme.of(context).colorScheme;

    if (tipo.contains('excluida') || tipo.contains('nao_reconhecido')) {
      return colorScheme.error;
    }

    if (tipo.contains('pausada')) {
      return Colors.orange.shade700;
    }

    if (tipo.contains('reproduzida') || tipo.contains('retomada')) {
      return Colors.green.shade700;
    }

    return colorScheme.primary;
  }

  Widget _filtros() {
    final tipos = _tiposDisponiveis;

    if (tipos.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: FilterChip(
              label: const Text('Todos'),
              selected: _tipoSelecionado == null,
              onSelected: (_) {
                setState(() {
                  _tipoSelecionado = null;
                });
              },
            ),
          ),
          ...tipos.map(
            (tipo) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: FilterChip(
                label: Text(_formatarTipo(tipo)),
                selected: _tipoSelecionado == tipo,
                onSelected: (_) {
                  setState(() {
                    _tipoSelecionado = tipo;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventoCard(HistoricoAcao evento) {
    final cor = _corPorTipo(context, evento.tipo);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: cor.withAlpha(28),
              child: Icon(_iconePorTipo(evento.tipo), color: cor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatarTipo(evento.tipo),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        _formatarData(evento.dataHora),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(evento.descricao),
                  if (evento.projetoId != null || evento.gravacaoId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (evento.projetoId != null)
                            Chip(
                              label: Text('Projeto ${evento.projetoId}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (evento.gravacaoId != null)
                            Chip(
                              label: Text('Gravacao ${evento.gravacaoId}'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventosFiltrados = _eventosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico'),
        actions: [
          IconButton(
            tooltip: _ouvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: _alternarEscutaVoz,
            icon: Icon(_ouvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarHistorico,
        child: Builder(
          builder: (context) {
            if (_carregando) {
              return const AppLoadingView(
                message: 'Carregando historico de acoes...',
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
                    onPressed: _carregarHistorico,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (_eventos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.history_rounded,
                    title: 'Nenhum evento registrado',
                    subtitle:
                        'Use comandos de voz, grave audios ou reproduza arquivos para popular o historico.',
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: eventosFiltrados.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox(height: AppSpacing.md)
                  : const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${eventosFiltrados.length} eventos',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _filtros(),
                    ],
                  );
                }

                return _eventoCard(eventosFiltrados[index - 1]);
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
    );
  }
}
