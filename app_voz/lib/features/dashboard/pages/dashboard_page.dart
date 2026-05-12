import 'package:flutter/material.dart';

import '../../../core/ui/app_empty_state.dart';
import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../models/usuario.dart';
import '../../../repositories/gravacao_repository.dart';
import '../../../repositories/projeto_repository.dart';

class DashboardPage extends StatefulWidget {
  final Usuario usuario;

  const DashboardPage({super.key, required this.usuario});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _carregando = true;
  String? _erro;

  List<Projeto> _projetos = [];
  List<Gravacao> _gravacoes = [];

  @override
  void initState() {
    super.initState();
    _carregarDashboard();
  }

  Future<void> _carregarDashboard() async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Usuário sem identificação para carregar o dashboard.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultados = await Future.wait([
        ProjetoRepository.instance.listarProjetosPorUsuario(usuarioId),
        GravacaoRepository.instance.listarGravacoesPorUsuario(usuarioId),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _projetos = resultados[0] as List<Projeto>;
        _gravacoes = resultados[1] as List<Gravacao>;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o dashboard: $e';
      });
    }
  }

  int get _duracaoTotalSegundos =>
      _gravacoes.fold(0, (total, item) => total + item.duracaoSegundos);

  Gravacao? get _ultimaGravacao => _gravacoes.isEmpty ? null : _gravacoes.first;

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
      return 'Data inválida';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano às $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDashboard,
        child: Builder(
          builder: (context) {
            if (_carregando) {
              return const AppLoadingView(
                message: 'Carregando indicadores do dashboard...',
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
                    onPressed: _carregarDashboard,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              );
            }

            if (_projetos.isEmpty && _gravacoes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.insights_outlined,
                    title: 'Sem dados suficientes ainda',
                    subtitle:
                        'Crie projetos e grave áudios para começar a visualizar indicadores aqui.',
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  'Resumo geral',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.folder_outlined,
                        title: 'Projetos',
                        value: _projetos.length.toString(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.library_music_outlined,
                        title: 'Gravações',
                        value: _gravacoes.length.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetricCard(
                  icon: Icons.timer_outlined,
                  title: 'Duração total',
                  value: _formatarDuracao(_duracaoTotalSegundos),
                  wide: true,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Última gravação',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_ultimaGravacao == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text('Nenhuma gravação encontrada até o momento.'),
                    ),
                  ),
                if (_ultimaGravacao != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: theme.colorScheme.primary
                                    .withOpacity(0.12),
                                child: Icon(
                                  Icons.mic_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  _ultimaGravacao!.nome,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Gravada em: ${_formatarData(_ultimaGravacao!.dataCriacao)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Duração: ${_formatarDuracao(_ultimaGravacao!.duracaoSegundos)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool wide;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            CircleAvatar(
              radius: wide ? 24 : 22,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
