import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/pages/login_page.dart';

const _kBrand = Color(0xFF6B3FA0);
const _kBrandLight = Color(0xFF9B6DDD);

class OnboardingPremiumPage extends StatefulWidget {
  const OnboardingPremiumPage({
    super.key,
    this.loginBuilder,
    this.salvarConcluido,
  });

  final WidgetBuilder? loginBuilder;
  final Future<void> Function()? salvarConcluido;

  @override
  State<OnboardingPremiumPage> createState() => _OnboardingPremiumPageState();
}

class _OnboardingPremiumPageState extends State<OnboardingPremiumPage> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _concluindo = false;

  static const int _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _salvarEConcluir() async {
    if (_concluindo) return;
    setState(() {
      _concluindo = true;
    });
    try {
      if (widget.salvarConcluido != null) {
        await widget.salvarConcluido!();
      } else {
        final config =
            await ConfiguracaoAppRepository.instance.buscarConfiguracao();
        await ConfiguracaoAppRepository.instance.salvarConfiguracao(
          config.copyWith(primeiraExecucaoConcluida: true),
        );
      }
    } catch (_) {
      // Even if save fails, proceed — don't block the user.
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: widget.loginBuilder ?? (_) => const LoginPage(),
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      unawaited(_salvarEConcluir());
    }
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0614),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0614), Color(0xFF13092A), Color(0xFF0C1225)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrandLight.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _currentPage < _totalPages - 1
                          ? TextButton(
                              key: const Key('onboarding_skip_button'),
                              onPressed: _concluindo
                                  ? null
                                  : () => unawaited(_salvarEConcluir()),
                              child: const Text(
                                'Pular',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    key: const Key('onboarding_page_view'),
                    controller: _pageController,
                    onPageChanged: (page) =>
                        setState(() => _currentPage = page),
                    children: const [
                      _OnboardingSlide1(),
                      _OnboardingSlide2(),
                      _OnboardingSlide3(),
                      _OnboardingSlide4(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_totalPages, (i) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == i ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? _kBrandLight
                                  : Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (_currentPage > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('onboarding_back_button'),
                                onPressed: _concluindo ? null : _previousPage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  minimumSize: const Size(0, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Voltar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: _currentPage > 0 ? 2 : 1,
                            child: ElevatedButton(
                              key: _currentPage < _totalPages - 1
                                  ? const Key('onboarding_next_button')
                                  : const Key('onboarding_comecar_button'),
                              onPressed: _concluindo
                                  ? null
                                  : (_currentPage < _totalPages - 1
                                      ? _nextPage
                                      : () => unawaited(_salvarEConcluir())),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kBrand,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: _concluindo &&
                                      _currentPage == _totalPages - 1
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _currentPage < _totalPages - 1
                                          ? 'Próximo'
                                          : 'Começar',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slides ──────────────────────────────────────────────────────────────────

class _OnboardingSlide1 extends StatelessWidget {
  const _OnboardingSlide1();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          const AppLogo(height: 108),
          const SizedBox(height: 14),
          _buildSoundWave(),
          const SizedBox(height: 18),
          const Text(
            'Touchless',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Controle sua música sem tocar no celular.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Um fluxo inteligente para criar projetos, gravar ideias e navegar pelo app usando voz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundWave() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.12),
          ),
        ),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.2),
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.42),
            boxShadow: [
              BoxShadow(
                color: _kBrand.withValues(alpha: 0.4),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _OnboardingSlide2 extends StatelessWidget {
  const _OnboardingSlide2();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          const _GlowIcon(icon: Icons.mic_rounded, size: 52),
          const SizedBox(height: 26),
          const Text(
            'Comandos que\nacompanham seu ritmo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Diga frases como "abrir projetos", "gravar" ou "minhas gravações" e continue focado no instrumento.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: const [
              _CommandChip(label: 'abrir projetos'),
              _CommandChip(label: 'gravar'),
              _CommandChip(label: 'minhas gravações'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlide3 extends StatelessWidget {
  const _OnboardingSlide3();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          const _GlowIcon(icon: Icons.folder_open_rounded, size: 52),
          const SizedBox(height: 26),
          const Text(
            'Suas ideias no lugar certo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Separe projetos, gravações e histórico em uma experiência feita para músicos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: const [
              _CommandChip(label: 'Projetos'),
              _CommandChip(label: 'Gravações'),
              _CommandChip(label: 'Histórico'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlide4 extends StatelessWidget {
  const _OnboardingSlide4();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          const _GlowIconCompound(),
          const SizedBox(height: 26),
          const Text(
            'Toque. Grave. Organize.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Use o celular no suporte, mantenha as mãos livres e deixe o Touchless cuidar do fluxo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Toque Começar para criar sua conta e usar o Touchless.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _GlowIcon extends StatelessWidget {
  const _GlowIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 36,
      height: size + 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kBrand.withValues(alpha: 0.18),
        boxShadow: [
          BoxShadow(
            color: _kBrand.withValues(alpha: 0.28),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: size, color: _kBrandLight),
    );
  }
}

class _GlowIconCompound extends StatelessWidget {
  const _GlowIconCompound();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kBrand.withValues(alpha: 0.18),
        boxShadow: [
          BoxShadow(
            color: _kBrand.withValues(alpha: 0.3),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 16,
            top: 18,
            child: Icon(Icons.music_note_rounded, size: 24, color: _kBrandLight),
          ),
          Icon(Icons.mic_rounded, size: 30, color: Colors.white),
          Positioned(
            right: 12,
            bottom: 16,
            child: Icon(
              Icons.folder_open_rounded,
              size: 22,
              color: _kBrandLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
