import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _flutterTts = FlutterTts();

  final FlutterTts _flutterTts;

  Future<void> initialize() async {
    await _flutterTts.setLanguage('pt-BR');
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> dispose() async {
    await _flutterTts.stop();
  }
}
