import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../home/pages/home_page.dart';
import '../../voices/services/voice_permission_service.dart';

const _kBrand = Color(0xFF6B3FA0);
const _kBrandLight = Color(0xFF9B6DDD);

class MicrophonePermissionPage extends StatefulWidget {
  const MicrophonePermissionPage({
    super.key,
    required this.usuario,
    this.voicePermissionService,
    this.homeBuilder,
  });

  final Usuario usuario;
  final VoicePermissionService? voicePermissionService;
  final Widget Function(Usuario usuario)? homeBuilder;

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
        _irParaHome();
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _verificando = false;
      });
    }
  }

  void _irParaHome() {
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
    setState(() {
      _solicitando = true;
    });
    try {
      final result = await _permissionService.requestMicrophone();
      if (!mounted) return;
      if (result == VoicePermissionResult.granted) {
        setState(() {
          _concedido = true;
          _feedbackMensagem =
              'Microfone liberado. Agora você pode controlar o app por voz.';
          _solicitando = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) _irParaHome();
        return;
      }
      setState(() {
        _concedido = false;
        _feedbackMensagem = _permissionService.guidanceMessage(result);
        _solicitando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _solicitando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0614),
        body: Center(
          child: CircularProgressIndicator(color: _kBrandLight),
        ),
      );
    }

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
            top: -80,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.12),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMicIcon(),
                    const SizedBox(height: 28),
                    const Text(
                      'Ative o controle por voz',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'O Touchless usa o microfone para reconhecer comandos como '
                      '"gravar", "abrir projetos" e "minhas gravações".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    if (_feedbackMensagem != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _concedido == true
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.orange.withValues(alpha: 0.10),
                          border: Border.all(
                            color: _concedido == true
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.orange.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _feedbackMensagem!,
                          key: const Key('mic_permission_feedback'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _concedido == true
                                ? Colors.greenAccent.shade100
                                : Colors.orange.shade200,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      key: const Key('mic_permission_allow_button'),
                      onPressed:
                          _solicitando || _concedido == true
                              ? null
                              : _solicitarPermissao,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
                                fontSize: 15,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('mic_permission_skip_button'),
                      onPressed: _solicitando ? null : _irParaHome,
                      child: const Text(
                        'Continuar sem microfone',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
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

  Widget _buildMicIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.12),
          ),
        ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.2),
          ),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.42),
            boxShadow: [
              BoxShadow(
                color: _kBrand.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, size: 26, color: Colors.white),
        ),
      ],
    );
  }
}
