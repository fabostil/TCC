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

  static const _kBrand = Color(0xFF6B3FA0);
  static const _kBrandLight = Color(0xFF9B6DDD);

  InputDecoration _fieldDeco({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      prefixIcon: Icon(icon, color: Colors.white54),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBrandLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
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
            top: -100,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
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
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  children: [
                    widget.logoBuilder?.call(context) ??
                        const AppLogo(height: 120),
                    const SizedBox(height: 14),
                    const Text(
                      'Touchless',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Entre para controlar gravações por voz',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    // Card glassmorphic
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              key: const Key('login_email_field'),
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white),
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
                              style: const TextStyle(color: Colors.white),
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
                                    color: Colors.white54,
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
                                child: const Text(
                                  'Esqueci minha senha',
                                  style: TextStyle(
                                    color: _kBrandLight,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            ElevatedButton(
                              key: const Key('login_submit_button'),
                              onPressed: _carregando || _carregandoGoogle
                                  ? null
                                  : _entrar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kBrand,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
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
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _carregando || _carregandoGoogle
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      widget.cadastroBuilder?.call(context) ??
                                      const CadastroPage(),
                                ),
                              );
                            },
                      child: const Text(
                        'Criar nova conta',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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
}
