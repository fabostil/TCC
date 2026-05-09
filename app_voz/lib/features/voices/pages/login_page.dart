import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../services/database_service.dart';
import '../../home/pages/home_page.dart';
import 'cadastro_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _carregando = false;
  bool _mostrarSenha = false;

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final Usuario? usuario = await DatabaseService.instance.autenticarUsuario(
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
        MaterialPageRoute(builder: (_) => HomePage(usuario: usuario)),
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
                const Icon(Icons.mic, size: 80, color: Colors.deepPurple),

                const SizedBox(height: 16),

                const Text(
                  'Assistente Musical',
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
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe seu e-mail.';
                    }

                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Informe um e-mail válido.';
                    }

                    return null;
                  },
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
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe sua senha.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _carregando ? null : _entrar,
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

                const SizedBox(height: 16),

                TextButton(
                  onPressed: _carregando
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CadastroPage(),
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
