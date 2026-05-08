import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      onStatus: (status) {
        print('Status reconhecimento de voz: $status');
      },
      onError: (error) {
        print('Erro reconhecimento de voz: $error');
      },
    );

    return _initialized;
  }

  Future<void> startListening(Function(String) onResult) async {
    final available = await initialize();

    if (!available) {
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
    }

    await _speech.listen(
      localeId: 'pt_BR',
      listenMode: stt.ListenMode.confirmation,
      onResult: (result) {
        onResult(result.recognizedWords);
      },
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }
}
