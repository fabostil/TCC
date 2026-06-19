import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../models/usuario.dart';
import '../../home/pages/home_page.dart';
import '../services/auth_service.dart';
import '../services/auth_validation_service.dart';
import '../services/google_auth_service.dart';
import '../widgets/google_sign_in_button.dart';
import 'cadastro_page.dart';

typedef LoginHomeBuilder = Widget Function(Usuario usuario);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.authService,
    this.homeBuilder,
    this.cadastroBuilder,
    this.logoBuilder,
  });

  final AuthService? authService;
  final LoginHomeBuilder? homeBuilder;
  final WidgetBuilder? cadastroBuilder;
  final WidgetBuilder? logoBuilder;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _passwordRecoveryMessage =
      'Esta versão do protótipo não possui recuperação automática por e-mail. '
      'Para continuar, entre com Google ou crie uma nova conta local.';

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _authValidationService = const AuthValidationService();

  bool _carregando = false;
  bool _carregandoGoogle = false;
  bool _mostrarSenha = false;

  AuthService get _authService => widget.authService ?? AuthService.instance;

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final Usuario? usuario = await _authService.autenticarUsuario(
        email: _emailController.text,
        senha: _senhaController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      if (usuario == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível entrar. Confira o e-mail e a senha.',
            ),
          ),
        );
        return;
      }

      _abrirHomeAutenticada(usuario);
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
                  'Não consegui concluir o login. Confira os dados e tente novamente.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _entrarComGoogle() async {
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
    } on AuthGoogleLoginException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      _mostrarMensagem(e.message);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      _mostrarMensagem(googleLoginGenericMessage);
    }
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
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

  Future<void> _mostrarRecuperacaoSenha() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperação de senha'),
        content: const Text(_passwordRecoveryMessage),
        actions: [
          TextButton(
            key: const Key('password_recovery_dismiss_button'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
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
          // Radial spotlight
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 0.80,
                colors: [
                  _kBrand.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Top-right blob
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 300,
              height: 300,
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
                  horizontal: 26,
                  vertical: 28,
                ),
                child: Column(
                  children: [
                    widget.logoBuilder?.call(context) ??
                        const AppLogo(height: 88),
                    const SizedBox(height: 12),
                    const Text(
                      'Touchless',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Suas gravações. Sua voz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
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
                              key: const Key('login_email_field'),
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
                              validator: _authValidationService.validarEmail,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('login_password_field'),
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
                              validator:
                                  _authValidationService.validarSenhaLogin,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('forgot_password_button'),
                                onPressed: _carregando || _carregandoGoogle
                                    ? null
                                    : _mostrarRecuperacaoSenha,
                                style: TextButton.styleFrom(
                                  foregroundColor: _kBrandLight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                                child: const Text(
                                  'Esqueci minha senha',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Primary button with glow
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: !_carregando && !_carregandoGoogle
                                    ? [
                                        BoxShadow(
                                          color: _kBrand.withValues(alpha: 0.45),
                                          blurRadius: 22,
                                          offset: const Offset(0, 6),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: ElevatedButton(
                                key: const Key('login_submit_button'),
                                onPressed: _carregando || _carregandoGoogle
                                    ? null
                                    : _entrar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kBrandMid,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      _kBrand.withValues(alpha: 0.4),
                                  minimumSize:
                                      const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                        'Entrar',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            GoogleSignInButton(
                              key: const Key('login_google_button'),
                              onPressed: _carregando || _carregandoGoogle
                                  ? null
                                  : _entrarComGoogle,
                              loading: _carregandoGoogle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Novo por aqui?',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                        TextButton(
                          onPressed: _carregando || _carregandoGoogle
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          widget.cadastroBuilder
                                                  ?.call(context) ??
                                          const CadastroPage(),
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
                            'Criar nova conta',
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
    );
  }
}
