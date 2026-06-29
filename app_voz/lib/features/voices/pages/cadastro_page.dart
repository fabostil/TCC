import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../models/usuario.dart';
import '../../home/pages/home_page.dart';
import '../services/auth_service.dart';
import '../services/auth_validation_service.dart';
import '../services/google_auth_service.dart';
import '../widgets/google_sign_in_button.dart';
import 'login_page.dart';

typedef CadastroHomeBuilder = Widget Function(Usuario usuario);

class CadastroPage extends StatefulWidget {
  const CadastroPage({
    super.key,
    this.authService,
    this.homeBuilder,
    this.loginBuilder,
    this.logoBuilder,
  });

  final AuthService? authService;
  final CadastroHomeBuilder? homeBuilder;
  final WidgetBuilder? loginBuilder;
  final WidgetBuilder? logoBuilder;

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  final _authValidationService = const AuthValidationService();

  bool _carregando = false;
  bool _carregandoGoogle = false;
  bool _mostrarSenha = false;

  AuthService get _authService => widget.authService ?? AuthService.instance;

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final sucesso = await _authService.cadastrarUsuario(
        nome: _nomeController.text,
        email: _emailController.text,
        senha: _senhaController.text,
      );

      if (!mounted) {
        return;
      }

      if (!sucesso) {
        setState(() {
          _carregando = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Essa conta já existe. Tente entrar ou use outro e-mail.',
            ),
          ),
        );
        return;
      }

      // Auto-login para fluxo atômico: conta criada, sessão salva na mesma etapa.
      Usuario? usuario;
      try {
        usuario = await _authService.autenticarUsuario(
          email: _emailController.text,
          senha: _senhaController.text,
        );
      } catch (_) {
        usuario = null;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      if (usuario != null) {
        _abrirHomeAutenticada(usuario);
        return;
      }

      // Fallback raro: auto-login falhou após cadastro bem-sucedido.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta criada com sucesso. Entre para continuar.'),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.loginBuilder?.call(context) ?? const LoginPage(),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingMessages.error(
              e,
              fallback:
                  'Não consegui criar sua conta. Confira os dados e tente novamente.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _cadastrarComGoogle() async {
    if (_carregando || _carregandoGoogle) {
      return;
    }

    setState(() {
      _carregandoGoogle = true;
    });

    try {
      final usuario = await _authService.entrarComGoogle();

      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      if (usuario == null) {
        _mostrarMensagem(googleLoginCanceledMessage);
        return;
      }

      _abrirHomeAutenticada(usuario);
    } on GoogleAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      _mostrarMensagem(e.message);
    } on AuthGoogleLoginException {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      _mostrarMensagem(authGoogleSignupPreparationMessage);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      _mostrarMensagem(authGoogleSignupPreparationMessage);
    }
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  void _abrirHomeAutenticada(Usuario usuario) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            widget.homeBuilder?.call(usuario) ?? HomePage(usuario: usuario),
      ),
      (route) => false,
    );
  }

  static const _kBgTop      = Color(0xFF08041A);
  static const _kBgMid      = Color(0xFF14082E);
  static const _kBgBot      = Color(0xFF0C1130);
  static const _kBrand      = Color(0xFF7B35C8);
  static const _kBrandMid   = Color(0xFF9748DA);
  static const _kBrandLight = Color(0xFFB870F0);
  static const _kAccent     = Color(0xFFC040A0);

  InputDecoration _fieldDeco({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      floatingLabelStyle: const TextStyle(color: _kBrandLight),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBrandLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Deep gradient
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
          // Radial spotlight (left-biased for cadastro variety)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.5),
                radius: 0.80,
                colors: [
                  _kBrand.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Top-left accent blob
          Positioned(
            top: -100,
            left: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kAccent.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Back button row
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white60,
                          size: 20,
                        ),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          widget.logoBuilder?.call(context) ??
                              const AppLogo(height: 72),
                          const SizedBox(height: 10),
                          const Text(
                            'Criar conta',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Use Google ou crie uma conta local.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),
                          GoogleSignInButton(
                            key: const Key('cadastro_google_button'),
                            onPressed: _carregando || _carregandoGoogle
                                ? null
                                : _cadastrarComGoogle,
                            loading: _carregandoGoogle,
                          ),
                          const SizedBox(height: 18),
                          // Glassmorphism card
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  TextFormField(
                                    key: const Key('cadastro_nome_field'),
                                    controller: _nomeController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    decoration: _fieldDeco(
                                      label: 'Nome',
                                      icon: Icons.person_outline,
                                    ),
                                    validator:
                                        _authValidationService.validarNome,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    key: const Key('cadastro_email_field'),
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    decoration: _fieldDeco(
                                      label: 'E-mail',
                                      icon: Icons.email_outlined,
                                    ),
                                    validator:
                                        _authValidationService.validarEmail,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    key: const Key('cadastro_password_field'),
                                    controller: _senhaController,
                                    obscureText: !_mostrarSenha,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    decoration: _fieldDeco(
                                      label: 'Senha',
                                      icon: Icons.lock_outline,
                                      suffix: IconButton(
                                        tooltip: _mostrarSenha
                                            ? 'Ocultar senha'
                                            : 'Mostrar senha',
                                        icon: Icon(
                                          _mostrarSenha
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: Colors.white38,
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                          () => _mostrarSenha = !_mostrarSenha,
                                        ),
                                      ),
                                    ),
                                    validator: _authValidationService
                                        .validarSenhaCadastro,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    key: const Key(
                                      'cadastro_confirm_password_field',
                                    ),
                                    controller: _confirmarSenhaController,
                                    obscureText: !_mostrarSenha,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                    decoration: _fieldDeco(
                                      label: 'Confirmar senha',
                                      icon: Icons.lock_person_outlined,
                                    ),
                                    validator: (value) =>
                                        _authValidationService
                                            .validarConfirmacaoSenha(
                                              value,
                                              _senhaController.text,
                                            ),
                                  ),
                                  const SizedBox(height: 22),
                                  // Primary button with glow
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow:
                                          !_carregando && !_carregandoGoogle
                                              ? [
                                                  BoxShadow(
                                                    color: _kBrand
                                                        .withValues(alpha: 0.45),
                                                    blurRadius: 22,
                                                    offset: const Offset(0, 6),
                                                  ),
                                                ]
                                              : null,
                                    ),
                                    child: ElevatedButton(
                                      key: const Key('cadastro_submit_button'),
                                      onPressed:
                                          _carregando || _carregandoGoogle
                                              ? null
                                              : _cadastrar,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _kBrandMid,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            _kBrand.withValues(alpha: 0.4),
                                        minimumSize:
                                            const Size(double.infinity, 54),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _carregando
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              'Cadastrar com e-mail',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Já tem conta?',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: _carregando || _carregandoGoogle
                                    ? null
                                    : () {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                widget.loginBuilder
                                                        ?.call(context) ??
                                                const LoginPage(),
                                          ),
                                        );
                                      },
                                style: TextButton.styleFrom(
                                  foregroundColor: _kBrandLight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
                                child: const Text(
                                  'Ja tenho uma conta',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
