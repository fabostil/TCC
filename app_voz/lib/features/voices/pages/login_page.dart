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
      'Este protótipo usa autenticação local no dispositivo. Por segurança, '
      'a recuperação automática por e-mail não está disponível nesta versão. '
      'Se você usa uma conta Google, entre com o botão ‘Entrar com Google’. '
      'Para uma conta local, crie uma nova conta ou solicite redefinição ao '
      'responsável pelo app.';

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
                  'Entre para controlar gravações por voz',
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
                      tooltip: _mostrarSenha
                          ? 'Ocultar senha'
                          : 'Mostrar senha',
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

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgot_password_button'),
                    onPressed: _carregando || _carregandoGoogle
                        ? null
                        : _mostrarRecuperacaoSenha,
                    child: const Text('Esqueci minha senha'),
                  ),
                ),

                const SizedBox(height: 12),

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
