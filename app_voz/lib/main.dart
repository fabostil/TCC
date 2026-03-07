import 'package:flutter/material.dart';

import 'features/voices/pages/voice_page.dart';

void main() {
  runApp(const AppVoz());
}

class AppVoz extends StatelessWidget {
  const AppVoz({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistente para Músicos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const VoicePage(),
    );
  }
}
