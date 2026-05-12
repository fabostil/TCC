import 'package:flutter/material.dart';

import '../../../core/ui/app_spacing.dart';
import '../../../models/usuario.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../voices/pages/login_page.dart';
import '../../voices/pages/voice_page.dart';

class HomePage extends StatelessWidget {
  final Usuario usuario;

  const HomePage({super.key, required this.usuario});

  void _sair(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _abrirNovoProjeto(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  void _abrirProjetos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: usuario),
      ),
    );
  }

  void _abrirAssistente(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoicePage(usuario: usuario)),
    );
  }

  void _abrirGravacoes(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: usuario),
      ),
    );
  }

  void _abrirDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardPage(usuario: usuario),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente Musical'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: () => _sair(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.14),
                    theme.colorScheme.secondary.withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá, ${usuario.nome}',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Organize ideias musicais, grave com rapidez e acompanhe seus projetos com uma experiência mais fluida.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('Atalhos', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.add_circle_outline_rounded,
              title: 'Novo projeto',
              subtitle: 'Crie um projeto musical e vá direto para o editor.',
              onTap: () => _abrirNovoProjeto(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.mic_none_rounded,
              title: 'Assistente de voz',
              subtitle: 'Use comandos para iniciar, pausar e encerrar gravações.',
              onTap: () => _abrirAssistente(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.folder_outlined,
              title: 'Meus projetos',
              subtitle: 'Acompanhe os projetos criados e seus detalhes.',
              onTap: () => _abrirProjetos(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.library_music_outlined,
              title: 'Minhas gravações',
              subtitle: 'Reproduza, renomeie e exclua gravações salvas.',
              onTap: () => _abrirGravacoes(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.insights_outlined,
              title: 'Dashboard',
              subtitle: 'Visualize métricas e resumos de uso do sistema.',
              onTap: () => _abrirDashboard(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
