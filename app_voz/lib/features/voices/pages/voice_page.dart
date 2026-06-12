import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import 'login_page.dart';
import '../services/speech_service.dart';

class VoicePage extends StatefulWidget {
  final Usuario usuario;

  const VoicePage({super.key, required this.usuario});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService speech = SpeechService();

  bool listening = false;
  bool _isContinuousListening = false; // Flag para controlar o loop infinito

  String text = 'Pressione o microfone para iniciar a escuta contínua';
  String ultimoComando = 'Nenhum comando executado ainda.';

  Future<void> toggleListening() async {
    if (!_isContinuousListening) {
      _isContinuousListening = true;
      _iniciarEscutaContinua();
    } else {
      _isContinuousListening = false;
      await speech.stopListening();

      if (mounted) {
        setState(() {
          listening = false;
          text = 'Pressione o microfone e fale';
          ultimoComando = 'Escuta contínua encerrada manualmente.';
        });
      }
    }
  }

  Future<void> _iniciarEscutaContinua() async {
    // Trava de segurança: se o usuário desligou ou a tela fechou, cancela o loop
    if (!_isContinuousListening || !mounted) return;

    await speech.startListening(
      onResult: (result) {
        setState(() {
          text = result;
        });
        handleVoiceCommand(result);
      },
      onStatus: (status) async {
        if (!mounted) return;

        if (status == 'listening') {
          setState(() {
            listening = true;
            ultimoComando = 'Estou ouvindo ativamente...';
          });
        }

        // O sistema cortou a escuta por silêncio ('done' ou 'notListening')
        if (status == 'done' || status == 'notListening') {
          if (_isContinuousListening) {
            // Aplicamos um delay de 700ms para o microfone ser liberado pelo sistema e religamos
            await Future.delayed(const Duration(milliseconds: 700));
            _iniciarEscutaContinua();
          } else {
            setState(() {
              listening = false;
            });
          }
        }
      },
      onError: (error) async {
        if (!mounted) return;

        // O timeout de silêncio do plugin vem como um erro. Apenas reiniciamos.
        if (error == 'error_speech_timeout') {
          if (_isContinuousListening) {
            await Future.delayed(const Duration(milliseconds: 700));
            _iniciarEscutaContinua();
          }
          return;
        }

        // Para outros erros (ex: falha de áudio), avisamos na UI e tentamos de novo com delay maior
        setState(() {
          listening = false;
          ultimoComando = 'Tentando reconectar (Erro: $error)...';
        });

        if (_isContinuousListening) {
          await Future.delayed(const Duration(seconds: 2));
          _iniciarEscutaContinua();
        }
      },
    );
  }

  void clearText() {
    setState(() {
      text = 'Pressione o microfone e fale';
      ultimoComando = 'Texto limpo.';
    });
  }

  void handleVoiceCommand(String command) {
    final cmd = command.toLowerCase().trim();

    if (cmd.isEmpty) return;

    if (cmd.contains('limpar')) {
      clearText();
      return;
    }

    if (cmd.contains('iniciar gravação') ||
        cmd.contains('começar gravação') ||
        cmd.contains('gravar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: iniciar gravação';
      });
      return;
    }

    if (cmd.contains('pausar gravação') || cmd.contains('pausar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: pausar gravação';
      });
      return;
    }

    if (cmd.contains('retomar gravação') ||
        cmd.contains('continuar gravação')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: retomar gravação';
      });
      return;
    }

    if (cmd.contains('encerrar gravação') ||
        cmd.contains('parar gravação') ||
        cmd.contains('finalizar gravação')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: encerrar gravação';
      });
      return;
    }

    if (cmd.contains('listar gravações') || cmd.contains('mostrar gravações')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: listar gravações';
      });
      return;
    }

    if (cmd.contains('criar marcador') || cmd.contains('marcar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: criar marcador';
      });
      return;
    }

    setState(() {
      ultimoComando = 'Comando não mapeado na interface.';
    });
  }

  void sair() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _isContinuousListening = false; // Garante que o loop morra ao sair da tela
    speech.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, ${widget.usuario.nome}'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: sair,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.music_note, size: 56, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text(
              'Assistente de Voz',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use comandos como: iniciar gravação, pausar gravação, retomar gravação ou encerrar gravação.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                ultimoComando,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'micButtonVoicePage',
                  onPressed: toggleListening,
                  backgroundColor: _isContinuousListening
                      ? Colors.red
                      : Colors.blue,
                  child: Icon(
                    _isContinuousListening ? Icons.mic : Icons.mic_none,
                  ),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'clearButtonVoicePage',
                  onPressed: clearText,
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.clear),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
