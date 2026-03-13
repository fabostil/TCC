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

  void toggleListening() async {
    if (!listening) {
      bool available = await speech.initialize();

      if (available) {
        setState(() => listening = true);

        await speech.startListening((result) {
          setState(() {
            text = result;
          });

          handleVoiceCommand(result);
        });
      }
    } else {
      setState(() => listening = false);
      await speech.stopListening();
    }
  }

  void clearText() {
    setState(() {
      text = "Pressione o microfone e fale";
    });
  }

  void handleVoiceCommand(String command) {
    final cmd = command.toLowerCase();
    if (cmd.contains("limpar")) {
      clearText();
    }
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
                FloatingActionButton(
                  onPressed: toggleListening,
                  backgroundColor: listening ? Colors.red : Colors.blue,
                  child: Icon(listening ? Icons.mic : Icons.mic_none),
                ),
                const SizedBox(width: 16),
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
