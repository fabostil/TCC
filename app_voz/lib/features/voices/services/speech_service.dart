import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService() : _speech = stt.SpeechToText();

  final stt.SpeechToText _speech;

  Future<bool> initialize() async {
    return _speech.initialize();
  }

  bool get isListening => _speech.isListening;

  Future<void> startListening(void Function(String result) onResult) async {
    if (_speech.isListening) {
      return;
    }

    await _speech.listen(
      localeId: 'pt_BR',
      listenMode: stt.ListenMode.confirmation,
      onResult: (result) => onResult(result.recognizedWords.trim()),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }
}
