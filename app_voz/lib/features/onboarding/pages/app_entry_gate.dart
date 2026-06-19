import 'package:flutter/material.dart';

import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/pages/cadastro_page.dart';
import '../../voices/pages/login_page.dart';
import 'microphone_permission_page.dart';
import 'onboarding_premium_page.dart';

/// Gate inicial: decide entre OnboardingPremiumPage e LoginPage.
///
/// Usa [primeiraExecucaoConcluida] do banco para decidir se exibe o
/// onboarding. Se já concluído, vai direto ao LoginPage com o homeBuilder
/// correto (MicrophonePermissionPage → HomePage).
class AppEntryGate extends StatefulWidget {
  const AppEntryGate({
    super.key,
    this.homeBuilder,
    this.overrideLoginBuilder,
    this.buscarConfiguracao,
    this.salvarConfiguracao,
  });

  final Widget Function(Usuario)? homeBuilder;
  final WidgetBuilder? overrideLoginBuilder;
  final Future<ConfiguracaoApp> Function()? buscarConfiguracao;
  final Future<void> Function(ConfiguracaoApp)? salvarConfiguracao;

  @override
  State<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<AppEntryGate> {
  ConfiguracaoApp? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final buscar =
          widget.buscarConfiguracao ??
          ConfiguracaoAppRepository.instance.buscarConfiguracao;
      final config = await buscar();
      if (mounted) {
        setState(() {
          _config = config;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildHome(Usuario usuario) {
    return widget.homeBuilder?.call(usuario) ??
        MicrophonePermissionPage(usuario: usuario);
  }

  Widget _buildLoginPage(BuildContext context) {
    if (widget.overrideLoginBuilder != null) {
      return widget.overrideLoginBuilder!(context);
    }
    return LoginPage(
      homeBuilder: _buildHome,
      cadastroBuilder: _buildCadastroPage,
    );
  }

  Widget _buildCadastroPage(BuildContext context) {
    return CadastroPage(
      homeBuilder: _buildHome,
      loginBuilder: _buildLoginPage,
    );
  }

  Future<void> _salvarConcluido() async {
    final config =
        _config ?? await ConfiguracaoAppRepository.instance.buscarConfiguracao();
    final updated = config.copyWith(primeiraExecucaoConcluida: true);
    final salvar =
        widget.salvarConfiguracao ??
        ConfiguracaoAppRepository.instance.salvarConfiguracao;
    await salvar(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0614),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF9B6DDD)),
        ),
      );
    }

    final config = _config;
    final onboardingConcluido = config?.primeiraExecucaoConcluida ?? false;

    if (!onboardingConcluido) {
      return OnboardingPremiumPage(
        loginBuilder: _buildLoginPage,
        salvarConcluido: _salvarConcluido,
      );
    }

    return _buildLoginPage(context);
  }
}
