import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../repositories/usuario_repository.dart';
import '../../home/pages/home_page.dart';
import '../services/auth_validation_service.dart';
import '../services/google_auth_service.dart';
import '../widgets/google_sign_in_button.dart';
import 'login_page.dart';

class CadastroPage extends StatefulWidget {
  const CadastroPage({super.key});

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

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final sucesso = await UsuarioRepository.instance.cadastrarUsuario(
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
          const SnackBar(content: Text('Este e-mail ja esta cadastrado.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastro criado. Para verificar a conta, entre com Google.',
          ),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
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
      ).showSnackBar(SnackBar(content: Text('Erro ao cadastrar: $e')));
    }
  }

  Future<void> _cadastrarComGoogle() async {
    setState(() {
      _carregandoGoogle = true;
    });

    try {
      final usuario = await GoogleAuthService.instance.entrarComGoogle();

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
        MaterialPageRoute(builder: (_) => HomePage(usuario: usuario)),
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoGoogle = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cadastrar com Google: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const AppLogo(height: 96),

                const SizedBox(height: 16),

                const Text(
                  'Criar conta',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Use Google para criar uma conta verificada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),

                const SizedBox(height: 24),

                GoogleSignInButton(
                  onPressed: _carregando ? null : _cadastrarComGoogle,
                  loading: _carregandoGoogle,
                ),

                const SizedBox(height: 24),

                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: _authValidationService.validarNome,
                ),

                const SizedBox(height: 16),

                TextFormField(
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
                  validator: _authValidationService.validarSenhaCadastro,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmarSenhaController,
                  obscureText: !_mostrarSenha,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar senha',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => _authValidationService
                      .validarConfirmacaoSenha(value, _senhaController.text),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _carregando || _carregandoGoogle
                      ? null
                      : _cadastrar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: _carregando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cadastrar com e-mail'),
                ),

                const SizedBox(height: 16),

                TextButton(
                  onPressed: _carregando || _carregandoGoogle
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                  child: const Text('Ja tenho uma conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
