import 'package:flutter/material.dart';
import 'features/voices/pages/voice_page.dart';

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
