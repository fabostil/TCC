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

      setState(() {
        _carregando = false;
      });

      if (!sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Essa conta já existe. Tente entrar ou use outro e-mail.',
            ),
          ),
        );
        return;
      }

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
            top: -80,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.1),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Back button row
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          widget.logoBuilder?.call(context) ??
                              const AppLogo(height: 80),
                          const SizedBox(height: 10),
                          const Text(
                            'Criar conta',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use Google ou crie uma conta local.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          GoogleSignInButton(
                            key: const Key('cadastro_google_button'),
                            onPressed: _carregando || _carregandoGoogle
                                ? null
                                : _cadastrarComGoogle,
                            loading: _carregandoGoogle,
                          ),
                          const SizedBox(height: 20),
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
                                    key: const Key('cadastro_nome_field'),
                                    controller: _nomeController,
                                    style: const TextStyle(color: Colors.white),
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
                                    style: const TextStyle(color: Colors.white),
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
                                    style: const TextStyle(color: Colors.white),
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
                                  const SizedBox(height: 20),
                                  ElevatedButton(
                                    key: const Key('cadastro_submit_button'),
                                    onPressed: _carregando || _carregandoGoogle
                                        ? null
                                        : _cadastrar,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kBrand,
                                      foregroundColor: Colors.white,
                                      minimumSize:
                                          const Size(double.infinity, 52),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
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
                                              fontSize: 15,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
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
                            child: const Text(
                              'Ja tenho uma conta',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
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
