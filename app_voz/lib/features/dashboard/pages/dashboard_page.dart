import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/dashboard_action_metric.dart';
import '../../../models/gravacao.dart';
import '../../../models/historico_acao.dart';
import '../../../models/usuario.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/services/command_service.dart';
import '../controllers/dashboard_controller.dart';
import '../services/dashboard_service.dart';

class DashboardPage extends StatefulWidget {
  final Usuario usuario;

  const DashboardPage({super.key, required this.usuario});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with ContextualVoiceListeningMixin<DashboardPage> {
  final DashboardController _dashboardController = DashboardController();

  DashboardState get _dashboardState => _dashboardController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.dashboard;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando do dashboard...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  void initState() {
    super.initState();
    _dashboardController.addListener(_onDashboardStateChanged);
    voiceCommandDispatcher = VoiceCommandDispatcher(
      handlers: {
        VoiceCommandType.voltar: _handleVoltar,
        VoiceCommandType.abrirDashboard: _handleJaAberto,
      },
    );
    _carregarDashboard();
    scheduleVoiceListeningOnFirstFrame();
  }

  Future<VoiceCommandPageResult> _handleVoltar(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleJaAberto(CommandResult _) async {
    return VoiceCommandPageResult.handled(message: 'Dashboard ja esta aberto.');
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _dashboardController.removeListener(_onDashboardStateChanged);
    _dashboardController.dispose();
    super.dispose();
  }

  void _onDashboardStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarDashboard() {
    return _dashboardController.load(widget.usuario.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDashboard,
        child: Builder(
          builder: (context) {
            final dashboardState = _dashboardState;

            if (dashboardState.loading) {
              return const AppLoadingView(
                message: 'Carregando indicadores do dashboard...',
              );
            }

            if (dashboardState.error != null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text(
                    dashboardState.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _carregarDashboard,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            final dashboard = dashboardState.data;

            if (dashboard == null || dashboard.estaVazio) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.insights_outlined,
                    title: 'Sem dados suficientes ainda',
                    subtitle:
                        'Crie projetos, grave audios ou use comandos de voz para visualizar indicadores aqui.',
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text('Resumo geral', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                _MetricGrid(
                  children: [
                    _MetricCard(
                      icon: Icons.folder_outlined,
                      title: 'Projetos',
                      value: dashboard.totalProjetos.toString(),
                    ),
                    _MetricCard(
                      icon: Icons.library_music_outlined,
                      title: 'Gravacoes',
                      value: dashboard.totalGravacoes.toString(),
                    ),
                    _MetricCard(
                      icon: Icons.timer_outlined,
                      title: 'Duracao total',
                      value: _formatarDuracao(dashboard.duracaoTotalSegundos),
                    ),
                    _MetricCard(
                      icon: Icons.record_voice_over_outlined,
                      title: 'Comandos',
                      value: dashboard.totalComandos.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Comandos de voz', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                _MetricGrid(
                  children: [
                    _MetricCard(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Reconhecidos',
                      value: dashboard.comandosReconhecidos.toString(),
                      color: Colors.green.shade700,
                    ),
                    _MetricCard(
                      icon: Icons.help_outline_rounded,
                      title: 'Nao reconhecidos',
                      value: dashboard.comandosNaoReconhecidos.toString(),
                      color: theme.colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _UltimaGravacaoCard(
                  gravacao: dashboard.ultimaGravacao,
                  formatarData: _formatarData,
                  formatarDuracao: _formatarDuracao,
                ),
                const SizedBox(height: AppSpacing.xl),
                _AcoesPorTipoCard(
                  metricas: dashboard.acoesPorTipo,
                  formatarTipo: _formatarTipo,
                  iconePorTipo: _iconePorTipo,
                  corPorTipo: (tipo) => _corPorTipo(context, tipo),
                ),
                const SizedBox(height: AppSpacing.xl),
                _EventosRecentesCard(
                  eventos: dashboard.eventosRecentes,
                  formatarData: _formatarData,
                  formatarTipo: _formatarTipo,
                  iconePorTipo: _iconePorTipo,
                  corPorTipo: (tipo) => _corPorTipo(context, tipo),
                ),
                const SizedBox(height: AppSpacing.xl),
                _InsightsCard(insights: dashboard.insights),
              ],
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

class _MetricGrid extends StatelessWidget {
  final List<Widget> children;

  const _MetricGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final colunas = largura >= 560 ? 4 : 2;
        final itemWidth = (largura - (AppSpacing.sm * (colunas - 1))) / colunas;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? color;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metricColor = color ?? theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: metricColor.withAlpha(28),
              child: Icon(icon, color: metricColor),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _UltimaGravacaoCard extends StatelessWidget {
  final Gravacao? gravacao;
  final String Function(String dataIso) formatarData;
  final String Function(int segundos) formatarDuracao;

  const _UltimaGravacaoCard({
    required this.gravacao,
    required this.formatarData,
    required this.formatarDuracao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = gravacao;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ultima gravacao', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: item == null
                ? const Text('Nenhuma gravacao encontrada ate o momento.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primary
                                .withAlpha(28),
                            child: Icon(
                              Icons.mic_rounded,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              item.nome,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Gravada em: ${formatarData(item.dataCriacao)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Duracao: ${formatarDuracao(item.duracaoSegundos)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _AcoesPorTipoCard extends StatelessWidget {
  final List<DashboardActionMetric> metricas;
  final String Function(String tipo) formatarTipo;
  final IconData Function(String tipo) iconePorTipo;
  final Color Function(String tipo) corPorTipo;

  const _AcoesPorTipoCard({
    required this.metricas,
    required this.formatarTipo,
    required this.iconePorTipo,
    required this.corPorTipo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acoes por tipo', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: metricas.isEmpty
                ? const Text('Nenhuma acao registrada ainda.')
                : Column(
                    children: metricas
                        .map(
                          (metrica) => _ActionMetricTile(
                            icon: iconePorTipo(metrica.tipo),
                            color: corPorTipo(metrica.tipo),
                            title: formatarTipo(metrica.tipo),
                            value: metrica.total.toString(),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EventosRecentesCard extends StatelessWidget {
  final List<HistoricoAcao> eventos;
  final String Function(String dataIso) formatarData;
  final String Function(String tipo) formatarTipo;
  final IconData Function(String tipo) iconePorTipo;
  final Color Function(String tipo) corPorTipo;

  const _EventosRecentesCard({
    required this.eventos,
    required this.formatarData,
    required this.formatarTipo,
    required this.iconePorTipo,
    required this.corPorTipo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Eventos recentes', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: eventos.isEmpty
                ? const Text('Nenhum evento recente registrado.')
                : Column(
                    children: eventos
                        .map(
                          (evento) => _EventTile(
                            icon: iconePorTipo(evento.tipo),
                            color: corPorTipo(evento.tipo),
                            title: formatarTipo(evento.tipo),
                            subtitle: evento.descricao,
                            trailing: formatarData(evento.dataHora),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ActionMetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _ActionMetricTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withAlpha(28),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;

  const _EventTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withAlpha(28),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(trailing, style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final List<DashboardInsight> insights;

  const _InsightsCard({required this.insights});

  IconData _iconePorTipo(DashboardInsightType tipo) {
    switch (tipo) {
      case DashboardInsightType.producao:
        return Icons.music_note_outlined;
      case DashboardInsightType.organizacao:
        return Icons.folder_copy_outlined;
      case DashboardInsightType.voz:
        return Icons.record_voice_over_outlined;
      case DashboardInsightType.alerta:
        return Icons.warning_amber_rounded;
      case DashboardInsightType.historico:
        return Icons.timeline_outlined;
    }
  }

  Color _corPorPrioridade(
    BuildContext context,
    DashboardInsightPriority prioridade,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (prioridade) {
      case DashboardInsightPriority.alta:
        return colorScheme.error;
      case DashboardInsightPriority.media:
        return Colors.orange.shade700;
      case DashboardInsightPriority.baixa:
        return colorScheme.primary;
    }
  }

  String _rotuloPrioridade(DashboardInsightPriority prioridade) {
    switch (prioridade) {
      case DashboardInsightPriority.alta:
        return 'Alta';
      case DashboardInsightPriority.media:
        return 'Media';
      case DashboardInsightPriority.baixa:
        return 'Baixa';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Insights inteligentes', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: insights.isEmpty
                ? const Text(
                    'Ainda nao ha padroes suficientes para gerar recomendacoes.',
                  )
                : Column(
                    children: insights.map((insight) {
                      final color = _corPorPrioridade(
                        context,
                        insight.prioridade,
                      );

                      return _InsightTile(
                        icon: _iconePorTipo(insight.tipo),
                        color: color,
                        title: insight.titulo,
                        subtitle: insight.descricao,
                        priority: _rotuloPrioridade(insight.prioridade),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String priority;

  const _InsightTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withAlpha(28),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      priority,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
