import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const VoiceApp());
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VoicePage(),
    );
  }
}

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final stt.SpeechToText speech = stt.SpeechToText();

  bool listening = false;
  String text = "Pressione o microfone e fale";

  void toggleListening() async {
    if (!listening) {
      bool available = await speech.initialize();

      if (available) {
        setState(() {
          listening = true;
        });

        speech.listen(
          onResult: (result) {
            setState(() {
              text = result.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() {
        listening = false;
      });

      speech.stop();
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
