import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/historico_acao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/historico_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/services/command_service.dart';

class HistoricoPage extends StatefulWidget {
  final Usuario usuario;

  const HistoricoPage({super.key, required this.usuario});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage>
    with ContextualVoiceListeningMixin<HistoricoPage> {
  final List<HistoricoAcao> _eventos = [];
  final ScrollController _voiceScrollController = ScrollController();

  bool _carregando = true;
  String? _erro;
  String? _tipoSelecionado;

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  String get voiceOwnerId => VoicePageOwners.historico;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando do historico...';

  @override
  void initState() {
    super.initState();
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.history,
      goHome: _handleIrParaHome,
      openProjects: _handleAbrirProjetosGlobal,
      openRecordings: _handleAbrirGravacoesGlobal,
      openDashboard: _handleAbrirDashboard,
      openSettings: _handleAbrirConfiguracoesGlobal,
      openNewProject: _handleAbrirNovoProjetoGlobal,
      goBack: _handleVoltar,
    );
    voiceCommandDispatcher = VoiceCommandDispatcher(
      handlers: {
        VoiceCommandType.voltar: _handleVoltar,
        VoiceCommandType.abrirDashboard: _handleAbrirDashboard,
        VoiceCommandType.abrirHistorico: _handleJaAberto,
        VoiceCommandType.scrollBaixo: _handleScrollPorVoz,
        VoiceCommandType.scrollCima: _handleScrollPorVoz,
        VoiceCommandType.scrollTopo: _handleScrollPorVoz,
        VoiceCommandType.scrollFim: _handleScrollPorVoz,
      },
    );
    _carregarHistorico();
    scheduleVoiceListeningOnFirstFrame();
  }

  Future<VoiceCommandPageResult> _handleVoltar(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboard(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (!mounted) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleJaAberto(CommandResult _) async {
    return VoiceCommandPageResult.handled(message: 'Historico ja esta aberto.');
  }

  Future<VoiceCommandPageResult> _handleScrollPorVoz(
    CommandResult resultado,
  ) async {
    return await VoiceScrollHandler(
          controller: _voiceScrollController,
        ).handle(resultado) ??
        VoiceCommandPageResult.unavailable(recognized: resultado.recognized);
  }

  Future<VoiceCommandPageResult> _handleIrParaHome(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetosGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjetoGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirGravacoesGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirConfiguracoesGlobal(
    CommandResult _,
  ) async {
    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _navegarGlobal<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      await Navigator.push(context, route);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _voiceScrollController.dispose();
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
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = UserFacingMessages.dataLoadError;
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
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
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
                controller: _voiceScrollController,
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
                controller: _voiceScrollController,
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
              controller: _voiceScrollController,
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
