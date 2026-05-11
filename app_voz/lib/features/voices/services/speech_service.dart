import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  String? _localeId;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    final microphoneStatus = await Permission.microphone.request();

    if (!microphoneStatus.isGranted) {
      onError?.call('Permissão de microfone negada.');
      return false;
    }

    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      onStatus: (status) {
        print('Status reconhecimento de voz: $status');
        onStatus?.call(status);
      },
      onError: (error) {
        print('Erro reconhecimento de voz: ${error.errorMsg}');
        onError?.call(error.errorMsg);
      },
    );

    if (!_initialized) {
      onError?.call('Reconhecimento de voz indisponível neste dispositivo.');
      return false;
    }

    final locales = await _speech.locales();

    final ptBrLocale = locales.where((locale) {
      return locale.localeId.toLowerCase() == 'pt_br';
    }).toList();

    if (ptBrLocale.isNotEmpty) {
      _localeId = ptBrLocale.first.localeId;
    } else {
      final systemLocale = await _speech.systemLocale();
      _localeId = systemLocale?.localeId;
    }

    print('Locale usado: $_localeId');

    return true;
  }

  Future<void> startListening({
    required Function(String text) onResult,
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    final available = await initialize(onStatus: onStatus, onError: onError);

    if (!available) {
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await _speech.listen(
      localeId: _localeId,
      listenMode: stt.ListenMode.confirmation,
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: false,
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
