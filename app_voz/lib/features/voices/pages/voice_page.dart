import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
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
  String text = 'Pressione o microfone e fale';
  String ultimoComando = 'Nenhum comando executado ainda.';

  Future<void> toggleListening() async {
    if (!listening) {
      final bool available = await speech.initialize();

      if (available) {
        setState(() {
          listening = true;
          text = 'Ouvindo...';
        });

        await speech.startListening((result) {
          setState(() {
            text = result;
          });

          handleVoiceCommand(result);
        });
      } else {
        setState(() {
          text = 'Reconhecimento de voz indisponível.';
          ultimoComando = 'Não foi possível iniciar o microfone.';
        });
      }
    } else {
      setState(() {
        listening = false;
      });

      await speech.stopListening();
    }
  }

  void clearText() {
    setState(() {
      text = 'Pressione o microfone e fale';
      ultimoComando = 'Texto limpo.';
    });
  }

  void handleVoiceCommand(String command) {
    final cmd = command.toLowerCase().trim();

    if (cmd.isEmpty) {
      return;
    }

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

    setState(() {
      ultimoComando = 'Comando não reconhecido.';
    });
  }

  @override
  void dispose() {
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
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
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
                  heroTag: 'micButton',
                  onPressed: toggleListening,
                  backgroundColor: listening ? Colors.red : Colors.blue,
                  child: Icon(listening ? Icons.mic : Icons.mic_none),
                ),

                const SizedBox(width: 16),

                FloatingActionButton(
                  heroTag: 'clearButton',
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
