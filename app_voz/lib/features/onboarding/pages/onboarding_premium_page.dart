import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/pages/login_page.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _kBgTop      = Color(0xFF08041A);
const _kBgMid      = Color(0xFF14082E);
const _kBgBot      = Color(0xFF0C1130);
const _kBrand      = Color(0xFF7B35C8);
const _kBrandMid   = Color(0xFF9748DA);
const _kBrandLight = Color(0xFFB870F0);
const _kAccent     = Color(0xFFC040A0);  // magenta hint for energy

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
    setState(() { _concluindo = true; });
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
    } catch (_) {}
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
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      unawaited(_salvarEConcluir());
    }
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Deep gradient background ──────────────────────────────────────
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kBgTop, _kBgMid, _kBgBot],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // ── Radial spotlight — creates premium glow in the content area ───
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 0.85,
                colors: [
                  _kBrand.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // ── Top-right decorative blob ─────────────────────────────────────
          Positioned(
            top: -140,
            right: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kAccent.withValues(alpha: 0.12),
                    _kBrand.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // ── Bottom-left decorative blob ───────────────────────────────────
          Positioned(
            bottom: -120,
            left: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kBrandLight.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // ── Page content ─────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Skip row
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: _currentPage < _totalPages - 1
                          ? TextButton(
                              key: const Key('onboarding_skip_button'),
                              onPressed: _concluindo
                                  ? null
                                  : () => unawaited(_salvarEConcluir()),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white54,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Pular',
                                style: TextStyle(fontSize: 14),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                // Slides
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
                // Bottom nav
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 22,
                  ),
                  child: Column(
                    children: [
                      // Page dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_totalPages, (i) {
                          final active = _currentPage == i;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? _kBrandLight
                                  : Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: _kBrandLight
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      // Buttons row
                      Row(
                        children: [
                          if (_currentPage > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('onboarding_back_button'),
                                onPressed: _concluindo ? null : _previousPage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white60,
                                  side: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: 0.18),
                                  ),
                                  minimumSize: const Size(0, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Voltar',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: _currentPage > 0 ? 2 : 1,
                            child: _PrimaryButton(
                              buttonKey: _currentPage < _totalPages - 1
                                  ? const Key('onboarding_next_button')
                                  : const Key('onboarding_comecar_button'),
                              onPressed: _concluindo
                                  ? null
                                  : (_currentPage < _totalPages - 1
                                      ? _nextPage
                                      : () => unawaited(_salvarEConcluir())),
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
                                        letterSpacing: 0.3,
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const AppLogo(height: 100),
          const SizedBox(height: 20),
          // Large ripple hero
          const _HeroRipple(),
          const SizedBox(height: 22),
          const Text(
            'Touchless',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Mãos livres.\nMúsica sem parar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Crie projetos, grave ideias e navegue pelo app\napenas com a sua voz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OnboardingSlide2 extends StatelessWidget {
  const _OnboardingSlide2();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const _SlideIcon(icon: Icons.mic_rounded, size: 56),
          const SizedBox(height: 28),
          const Text(
            'Comandos que\nacompanham seu ritmo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Diga frases naturais e continue focado no instrumento.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: [
              _Chip(label: 'abrir projetos'),
              _Chip(label: 'gravar'),
              _Chip(label: 'minhas gravações'),
              _Chip(label: 'histórico'),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const _SlideIcon(icon: Icons.folder_open_rounded, size: 56),
          const SizedBox(height: 28),
          const Text(
            'Suas ideias no lugar certo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Projetos, gravações e histórico organizados para músicos que não param.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: [
              _Chip(label: 'Projetos'),
              _Chip(label: 'Gravações'),
              _Chip(label: 'Histórico'),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const _SlideIconCompound(),
          const SizedBox(height: 28),
          const Text(
            'Toque. Grave. Organize.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Apoie o celular no suporte, ative o Touchless e mantenha as mãos livres para tocar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: _kBrandLight.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Toque Começar para criar sua conta e ativar o controle por voz.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero ripple (Slide 1) ────────────────────────────────────────────────────

class _HeroRipple extends StatelessWidget {
  const _HeroRipple();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _kBrand.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Ring 3
          Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.14),
                width: 1.5,
              ),
            ),
          ),
          // Ring 2
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
          ),
          // Ring 1
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.2),
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),
          // Center core
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.7),
              boxShadow: [
                BoxShadow(
                  color: _kBrand.withValues(alpha: 0.55),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: _kAccent.withValues(alpha: 0.20),
                  blurRadius: 40,
                  spreadRadius: 8,
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
      ),
    );
  }
}

// ─── Slide icon (Slides 2-3) ─────────────────────────────────────────────────

class _SlideIcon extends StatelessWidget {
  const _SlideIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 48,
      height: size + 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: size + 48,
            height: size + 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),
          // Middle fill
          Container(
            width: size + 28,
            height: size + 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.14),
            ),
          ),
          // Inner core
          Container(
            width: size + 8,
            height: size + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.28),
              boxShadow: [
                BoxShadow(
                  color: _kBrand.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, size: size, color: _kBrandLight),
          ),
        ],
      ),
    );
  }
}

// ─── Slide 4 compound icon ────────────────────────────────────────────────────

class _SlideIconCompound extends StatelessWidget {
  const _SlideIconCompound();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.22),
              boxShadow: [
                BoxShadow(
                  color: _kBrand.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: _kAccent.withValues(alpha: 0.15),
                  blurRadius: 48,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          const Positioned(
            left: 16,
            top: 18,
            child: Icon(Icons.music_note_rounded, size: 26, color: _kBrandLight),
          ),
          const Icon(Icons.mic_rounded, size: 30, color: Colors.white),
          const Positioned(
            right: 12,
            bottom: 16,
            child: Icon(Icons.folder_open_rounded, size: 24, color: _kBrandLight),
          ),
        ],
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.15),
        border: Border.all(color: _kBrandLight.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kBrandLight,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Primary action button with glow ─────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.buttonKey,
    required this.onPressed,
    required this.child,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: _kBrand.withValues(alpha: 0.50),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBrandMid,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kBrand.withValues(alpha: 0.4),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: child,
      ),
    );
  }
}
