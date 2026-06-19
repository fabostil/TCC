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
  final SpeechResultGate _resultGate = SpeechResultGate();
  Function(String text)? _currentOnResult;
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
      _currentOnError?.call(
        'Permita o uso do microfone para controlar o app por voz.',
      );
      return false;
    }

    if (_initialized) {
      return true;
    }

    _initialized = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Status reconhecimento de voz: $status');
        if (status == 'done' || status == 'notListening') {
          final onResult = _currentOnResult;
          if (onResult != null) {
            _resultGate.finalizePending(onResult);
          }
        }
        _currentOnStatus?.call(status);
      },
      onError: (error) {
        debugPrint('Erro reconhecimento de voz: ${error.errorMsg}');
        _resultGate.clearPending();
        _currentOnResult = null;
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
    _currentOnResult = onResult;

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
            _resultGate.add(
              text,
              isFinal: result.finalResult,
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
    _resetResultState();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    _resetResultState();
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  void _resetResultState() {
    _resultGate.clearPending();
    _currentOnResult = null;
  }
}

/// Entrega comandos apenas quando o STT os marca como finais.
///
/// Se uma plataforma encerrar a sessão sem emitir `finalResult`, o último
/// parcial é considerado estável somente no status `done`/`notListening`.
class SpeechResultGate {
  SpeechResultGate({
    this.duplicateCooldown = const Duration(seconds: 2),
    this.debounceDuration = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration duplicateCooldown;
  final Duration debounceDuration;
  final DateTime Function() _now;

  String? _pendingText;
  String? _lastDeliveredText;
  DateTime? _lastDeliveredAt;
  Timer? _debounceTimer;

  void add(
    String text, {
    required bool isFinal,
    required void Function(String text) onResult,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _pendingText = trimmed;
    if (isFinal) {
      _debounceTimer?.cancel();
      developer.log(
        "[SpeechGate] isFinal='$trimmed' debounce=${debounceDuration.inMilliseconds}ms",
        name: 'SpeechService',
      );
      _debounceTimer = Timer(debounceDuration, () => finalizePending(onResult));
    }
  }

  void finalizePending(void Function(String text) onResult) {
    final hadTimer = _debounceTimer != null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final text = _pendingText;
    _pendingText = null;
    if (text == null || text.isEmpty) {
      return;
    }

    developer.log(
      "[SpeechGate] flush='$text' cancelledTimer=$hadTimer",
      name: 'SpeechService',
    );

    final now = _now();
    final normalized = _normalize(text);
    final lastDeliveredAt = _lastDeliveredAt;
    if (_lastDeliveredText == normalized &&
        lastDeliveredAt != null &&
        now.difference(lastDeliveredAt) < duplicateCooldown) {
      developer.log(
        "[SpeechGate] duplicate_suppressed='$text'",
        name: 'SpeechService',
      );
      return;
    }

    _lastDeliveredText = normalized;
    _lastDeliveredAt = now;
    developer.log(
      "[SpeechGate] delivering='$text'",
      name: 'SpeechService',
    );
    onResult(text);
  }

  void reset() {
    clearPending();
    _lastDeliveredText = null;
    _lastDeliveredAt = null;
  }

  void clearPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingText = null;
  }

  String _normalize(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
