import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../editor/pages/editor_page.dart';
import '../../voices/pages/voice_page.dart';
import '../../voices/pages/login_page.dart';

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

  void _abrirEditor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorPage(usuario: usuario)),
    );
  }

  void _abrirAssistente(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoicePage(usuario: usuario)),
    );
  }

  void _mostrarEmBreve(BuildContext context, String funcionalidade) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$funcionalidade será implementado em breve.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente Musical'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: () => _sair(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Olá, ${usuario.nome}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              'Organize suas ideias musicais e controle gravações usando comandos de voz.',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 32),

            _HomeCard(
              icon: Icons.add_circle,
              title: 'Novo projeto',
              subtitle: 'Crie um projeto musical e abra o editor.',
              onTap: () => _abrirEditor(context),
            ),

            const SizedBox(height: 16),

            _HomeCard(
              icon: Icons.mic,
              title: 'Assistente de voz',
              subtitle:
                  'Teste comandos como iniciar, pausar e encerrar gravação.',
              onTap: () => _abrirAssistente(context),
            ),

            const SizedBox(height: 16),

            _HomeCard(
              icon: Icons.folder,
              title: 'Meus projetos',
              subtitle: 'Veja seus projetos musicais salvos.',
              onTap: () => _mostrarEmBreve(context, 'Meus projetos'),
            ),

            const SizedBox(height: 16),

            _HomeCard(
              icon: Icons.library_music,
              title: 'Gravações',
              subtitle: 'Acesse gravações feitas no aplicativo.',
              onTap: () => _mostrarEmBreve(context, 'Gravações'),
            ),

            const SizedBox(height: 16),

            _HomeCard(
              icon: Icons.bar_chart,
              title: 'Dashboard',
              subtitle:
                  'Veja quantidade de projetos, gravações e comandos usados.',
              onTap: () => _mostrarEmBreve(context, 'Dashboard'),
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
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.deepPurple.withOpacity(0.12),
                child: Icon(icon, color: Colors.deepPurple, size: 28),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(subtitle, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
