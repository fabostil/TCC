import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      onStatus: (status) {
        print('Status reconhecimento de voz: $status');

        if (onStatus != null) {
          onStatus(status);
        }
      },
      onError: (error) {
        print('Erro reconhecimento de voz: ${error.errorMsg}');

        if (onError != null) {
          onError(error.errorMsg);
        }
      },
    );

    return _initialized;
  }

  Future<void> startListening({
    required Function(String text) onResult,
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    final available = await initialize(onStatus: onStatus, onError: onError);

    if (!available) {
      if (onError != null) {
        onError('Reconhecimento de voz indisponível.');
      }
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
    }

    await _speech.listen(
      localeId: 'pt_BR',
      listenMode: stt.ListenMode.dictation,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (result) {
        final text = result.recognizedWords.trim();

        if (text.isNotEmpty) {
          onResult(text);
        }
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
