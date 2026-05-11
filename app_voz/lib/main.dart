import 'package:flutter/material.dart';

import 'features/flutter_sound_test/pages/flutter_sound_test_page.dart';

void main() {
  runApp(const VoiceApp());
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teste Flutter Sound',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const FlutterSoundTestPage(),
    );
  }
}
