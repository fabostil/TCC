import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../home/pages/home_page.dart';
import '../../voices/services/voice_permission_service.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _kBgTop      = Color(0xFF08041A);
const _kBgMid      = Color(0xFF14082E);
const _kBgBot      = Color(0xFF0C1130);
const _kBrand      = Color(0xFF7B35C8);
const _kBrandMid   = Color(0xFF9748DA);
const _kBrandLight = Color(0xFFB870F0);
const _kAccent     = Color(0xFFC040A0);

class MicrophonePermissionPage extends StatefulWidget {
  const MicrophonePermissionPage({
    super.key,
    required this.usuario,
    this.voicePermissionService,
    this.homeBuilder,
    this.salvarResultadoPermissao,
  });

  final Usuario usuario;
  final VoicePermissionService? voicePermissionService;
  final Widget Function(Usuario usuario)? homeBuilder;
  final Future<void> Function({required bool comandosVozAtivos})?
      salvarResultadoPermissao;

  @override
  State<MicrophonePermissionPage> createState() =>
      _MicrophonePermissionPageState();
}

class _MicrophonePermissionPageState extends State<MicrophonePermissionPage> {
  bool _verificando = true;
  bool _solicitando = false;
  String? _feedbackMensagem;
  bool? _concedido;

  VoicePermissionService get _permissionService =>
      widget.voicePermissionService ?? const VoicePermissionService();

  @override
  void initState() {
    super.initState();
    unawaited(_verificarPermissaoAtual());
  }

  Future<void> _verificarPermissaoAtual() async {
    try {
      final result = await _permissionService.checkMicrophone();
      if (!mounted) return;
      if (result == VoicePermissionResult.granted) {
        _irParaHome(micConcedido: true);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() { _verificando = false; });
  }

  void _irParaHome({required bool micConcedido}) {
    unawaited(_salvarENavegar(micConcedido: micConcedido));
  }

  Future<void> _salvarENavegar({required bool micConcedido}) async {
    try {
      await widget.salvarResultadoPermissao
          ?.call(comandosVozAtivos: micConcedido);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.homeBuilder?.call(widget.usuario) ??
            HomePage(usuario: widget.usuario),
      ),
      (route) => false,
    );
  }

  Future<void> _solicitarPermissao() async {
    if (_solicitando) return;
    setState(() { _solicitando = true; });
    try {
      final result = await _permissionService.requestMicrophone();
      if (!mounted) return;
      if (result == VoicePermissionResult.granted) {
        setState(() {
          _concedido = true;
          _feedbackMensagem = 'Microfone liberado! Agora você pode controlar o app por voz.';
          _solicitando = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) _irParaHome(micConcedido: true);
        return;
      }
      setState(() {
        _concedido = false;
        _feedbackMensagem = _permissionService.guidanceMessage(result);
        _solicitando = false;
      });
    } catch (_) {
      if (mounted) setState(() { _solicitando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        backgroundColor: _kBgTop,
        body: Center(child: CircularProgressIndicator(color: _kBrandLight)),
      );
    }

    return Scaffold(
      backgroundColor: _kBgTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
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
          // Radial spotlight
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 0.80,
                colors: [
                  _kBrand.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Decorative top-right blob
          Positioned(
            top: -100,
            right: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kAccent.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hero mic
                    _buildMicHero(),
                    const SizedBox(height: 32),
                    const Text(
                      'Ative o controle por voz',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'O Touchless usa o microfone para reconhecer seus comandos em tempo real, sem tocar no celular.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Usage examples
                    _buildUsageRow(),
                    if (_feedbackMensagem != null) ...[
                      const SizedBox(height: 20),
                      _buildFeedback(),
                    ],
                    const SizedBox(height: 32),
                    // Allow button
                    _buildAllowButton(),
                    const SizedBox(height: 14),
                    // Skip button
                    TextButton(
                      key: const Key('mic_permission_skip_button'),
                      onPressed: _solicitando
                          ? null
                          : () => _irParaHome(micConcedido: false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Continuar sem microfone',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicHero() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring (border only)
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
          ),
          // Mid ring (border only)
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kBrandLight.withValues(alpha: 0.20),
                width: 1.5,
              ),
            ),
          ),
          // Inner filled ring
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.20),
            ),
          ),
          // Core
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kBrand.withValues(alpha: 0.70),
              boxShadow: [
                BoxShadow(
                  color: _kBrand.withValues(alpha: 0.55),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: _kAccent.withValues(alpha: 0.18),
                  blurRadius: 44,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded, size: 28, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MicUsageTag(label: '"gravar"', icon: Icons.circle),
        const SizedBox(width: 8),
        _MicUsageTag(label: '"projetos"', icon: Icons.circle),
        const SizedBox(width: 8),
        _MicUsageTag(label: '"histórico"', icon: Icons.circle),
      ],
    );
  }

  Widget _buildFeedback() {
    final ok = _concedido == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withValues(alpha: 0.10)
            : Colors.orange.withValues(alpha: 0.10),
        border: Border.all(
          color: ok
              ? Colors.green.withValues(alpha: 0.28)
              : Colors.orange.withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.info_outline,
            color: ok ? Colors.greenAccent.shade200 : Colors.orange.shade300,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _feedbackMensagem!,
              key: const Key('mic_permission_feedback'),
              style: TextStyle(
                color: ok
                    ? Colors.greenAccent.shade100
                    : Colors.orange.shade200,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllowButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: !_solicitando && _concedido != true
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
        key: const Key('mic_permission_allow_button'),
        onPressed: _solicitando || _concedido == true ? null : _solicitarPermissao,
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
        child: _solicitando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Permitir microfone',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

// ─── Mic usage tag ────────────────────────────────────────────────────────────

class _MicUsageTag extends StatelessWidget {
  const _MicUsageTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.14),
        border: Border.all(color: _kBrandLight.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kBrandLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
