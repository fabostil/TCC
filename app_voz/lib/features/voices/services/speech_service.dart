import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService._();

  static final SpeechService instance = SpeechService._();

  /// Mantem compatibilidade com codigo que ainda chama `SpeechService()`.
  factory SpeechService() => instance;

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  String? _localeId;
  Timer? _resultDebounceTimer;
  String? _pendingText;
  String? _lastDeliveredText;
  DateTime? _lastDeliveredAt;
  Function(String status)? _currentOnStatus;
  Function(String error)? _currentOnError;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    _currentOnStatus = onStatus;
    _currentOnError = onError;

    var microphoneStatus = await Permission.microphone.status;
    if (!microphoneStatus.isGranted) {
      microphoneStatus = await Permission.microphone.request();
    }

    if (!microphoneStatus.isGranted) {
      _currentOnError?.call('Permissão de microfone negada.');
      return false;
    }

    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Status reconhecimento de voz: $status');
        _currentOnStatus?.call(status);
      },
      onError: (error) {
        debugPrint('Erro reconhecimento de voz: ${error.errorMsg}');
        _currentOnError?.call(error.errorMsg);
      },
    );

    if (!_initialized) {
      _currentOnError?.call(
        'Reconhecimento de voz indisponível neste dispositivo.',
      );
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

    debugPrint('Locale usado: $_localeId');

    return true;
  }

  Future<bool> startListening({
    required Function(String text) onResult,
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    final available = await initialize(onStatus: onStatus, onError: onError);

    if (!available) {
      return false;
    }

    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _resetResultState();

    try {
      await _speech.listen(
        localeId: _localeId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 10),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          final text = result.recognizedWords.trim();

          if (text.isNotEmpty) {
            developer.log(
              "[STT_DEBUG] TEXTO RECEBIDO: '$text'",
              name: 'SpeechService',
            );
            _handleResultText(
              text,
              finalResult: result.finalResult,
              onResult: onResult,
            );
          }
        },
      );
    } catch (error, stackTrace) {
      developer.log(
        'speech_listen_failed',
        name: 'SpeechService',
        error: error,
        stackTrace: stackTrace,
      );
      onError?.call('Não foi possível iniciar a escuta de voz.');
      return false;
    }

    return true;
  }

  Future<void> stopListening() async {
    _clearResultDebounce();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    _clearResultDebounce();
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  void _handleResultText(
    String text, {
    required bool finalResult,
    required Function(String text) onResult,
  }) {
    _pendingText = text;
    _resultDebounceTimer?.cancel();

    if (finalResult) {
      _deliverPendingResult(onResult);
      return;
    }

    _resultDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      _deliverPendingResult(onResult);
    });
  }

  void _deliverPendingResult(Function(String text) onResult) {
    final text = _pendingText?.trim();
    if (text == null || text.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final normalized = _normalizeForDedup(text);
    final lastDeliveredAt = _lastDeliveredAt;

    if (_lastDeliveredText == normalized &&
        lastDeliveredAt != null &&
        now.difference(lastDeliveredAt) < const Duration(seconds: 2)) {
      return;
    }

    _lastDeliveredText = normalized;
    _lastDeliveredAt = now;
    onResult(text);
  }

  String _normalizeForDedup(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _resetResultState() {
    _clearResultDebounce();
    _pendingText = null;
    _lastDeliveredText = null;
    _lastDeliveredAt = null;
  }

  void _clearResultDebounce() {
    _resultDebounceTimer?.cancel();
    _resultDebounceTimer = null;
  }
}
