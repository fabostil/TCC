import 'package:flutter/material.dart';
import '../services/speech_service.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService speech = SpeechService();

  bool listening = false;
  String text = "Pressione o microfone e fale";

  // Alterna o microfone
  void toggleListening() async {
    if (!listening) {
      bool available = await speech.initialize();

      if (available) {
        setState(() => listening = true);

        speech.startListening((result) {
          setState(() {
            text = result;
          });

          // Aqui você pode adicionar comandos de voz
          handleVoiceCommand(result);
        });
      }
    } else {
      setState(() => listening = false);
      speech.stopListening();
    }
  }

  // Limpa o texto da tela
  void clearText() {
    setState(() {
      text = "Pressione o microfone e fale";
    });
  }

  // Função para interpretar comandos de voz
  void handleVoiceCommand(String command) {
    final cmd = command.toLowerCase();
    if (cmd.contains("limpar")) {
      clearText();
    }
    // Exemplo: adicionar mais comandos
    // else if (cmd.contains("abrir mapa")) {
    //   Navigator.pushNamed(context, '/mapa');
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Assistente de Voz")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Botão microfone
                FloatingActionButton(
                  onPressed: toggleListening,
                  backgroundColor: listening ? Colors.red : Colors.blue,
                  child: Icon(listening ? Icons.mic : Icons.mic_none),
                ),
                const SizedBox(width: 16),
                // Botão limpar
                FloatingActionButton(
                  onPressed: clearText,
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.clear),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
