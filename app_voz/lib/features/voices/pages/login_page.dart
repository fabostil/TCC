import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
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
          const SnackBar(content: Text('E-mail ou senha incorretos.')),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.homeBuilder?.call(usuario) ?? HomePage(usuario: usuario),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao entrar: $e')));
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
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.homeBuilder?.call(usuario) ?? HomePage(usuario: usuario),
        ),
      );
    } on GoogleAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } on AuthGoogleLoginException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível preparar sua conta. Tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                widget.logoBuilder?.call(context) ?? const AppLogo(height: 112),

                const SizedBox(height: 16),

                const Text(
                  'Touchless',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Entre para controlar gravacoes por voz',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 32),

                TextFormField(
                  key: const Key('login_email_field'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: _authValidationService.validarEmail,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  key: const Key('login_password_field'),
                  controller: _senhaController,
                  obscureText: !_mostrarSenha,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _mostrarSenha ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _mostrarSenha = !_mostrarSenha;
                        });
                      },
                    ),
                  ),
                  validator: _authValidationService.validarSenhaLogin,
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  key: const Key('login_submit_button'),
                  onPressed: _carregando || _carregandoGoogle ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: _carregando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Entrar'),
                ),

                const SizedBox(height: 12),

                GoogleSignInButton(
                  key: const Key('login_google_button'),
                  onPressed: _carregando || _carregandoGoogle
                      ? null
                      : _entrarComGoogle,
                  loading: _carregandoGoogle,
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
                  child: const Text('Criar nova conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
