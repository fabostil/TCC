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
        setState(() {
          listening = true;
        });

        speech.startListening((result) {
          setState(() {
            text = result;
          });
        });
      }
    } else {
      setState(() {
        listening = false;
      });

      speech.stopListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Assistente de Voz")),
      body: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 24),
          textAlign: TextAlign.center,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: toggleListening,
        child: Icon(listening ? Icons.mic : Icons.mic_none),
      ),
    );
  }
}
