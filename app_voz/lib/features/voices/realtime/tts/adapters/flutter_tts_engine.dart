import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../coordination/voice_session_manager.dart';
import '../../dispatch/contratos/audio_output_guard.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../stub_text_to_speech_engine.dart';
import '../text_to_speech_engine.dart';

abstract class FlutterTtsClient {
  Future<dynamic> getLanguages();

  Future<dynamic> setLanguage(String language);

  Future<dynamic> setSpeechRate(double rate);

  Future<dynamic> setPitch(double pitch);

  Future<dynamic> setVolume(double volume);

  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion);

  Future<dynamic> speak(String text);

  Future<dynamic> stop();

  void setCompletionHandler(VoidCallback callback);

  void setCancelHandler(VoidCallback callback);

  void setErrorHandler(Function(dynamic message) handler);
}

class PluginFlutterTtsClient implements FlutterTtsClient {
  PluginFlutterTtsClient({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  @override
  Future<dynamic> getLanguages() => _flutterTts.getLanguages;

  @override
  Future<dynamic> setLanguage(String language) =>
      _flutterTts.setLanguage(language);

  @override
  Future<dynamic> setSpeechRate(double rate) => _flutterTts.setSpeechRate(rate);

  @override
  Future<dynamic> setPitch(double pitch) => _flutterTts.setPitch(pitch);

  @override
  Future<dynamic> setVolume(double volume) => _flutterTts.setVolume(volume);

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      _flutterTts.awaitSpeakCompletion(awaitCompletion);

  @override
  Future<dynamic> speak(String text) => _flutterTts.speak(text);

  @override
  Future<dynamic> stop() => _flutterTts.stop();

  @override
  void setCompletionHandler(VoidCallback callback) {
    _flutterTts.setCompletionHandler(callback);
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    _flutterTts.setCancelHandler(callback);
  }

  @override
  void setErrorHandler(Function(dynamic message) handler) {
    _flutterTts.setErrorHandler(handler);
  }
}

class FlutterTtsEngine implements TextToSpeechEngine {
  FlutterTtsEngine({
    VoiceRealtimeEventBus? eventBus,
    FlutterTtsClient? client,
    TextToSpeechEngine? fallback,
    AudioOutputGuard? audioOutputGuard,
    this.language = 'pt-BR',
    this.fallbackLanguage = 'pt',
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _client = client ?? PluginFlutterTtsClient(),
       _fallback =
           fallback ??
           StubTextToSpeechEngine(
             eventBus: eventBus ?? VoiceRealtimeEventBus.instance,
           ),
       _audioOutputGuard =
           audioOutputGuard ??
           LazyAudioOutputGuard(() => VoiceSessionManager.instance);

  static const String _ownerId = 'flutter_tts_engine';

  final VoiceRealtimeEventBus eventBus;
  final FlutterTtsClient _client;
  final TextToSpeechEngine _fallback;
  final AudioOutputGuard _audioOutputGuard;
  final String language;
  final String fallbackLanguage;
  final double speechRate;
  final double pitch;
  final double volume;

  Future<void>? _configuration;
  var _disposed = false;
  var _usingFallback = false;
  var _speaking = false;
  String? _activeCorrelationId;
  String? _selectedLanguage;

  @override
  Future<void> speak(String text, String correlationId) async {
    final normalizedText = text.trim();
    if (_disposed || normalizedText.isEmpty) {
      return;
    }

    await stop();

    if (_usingFallback) {
      await _fallback.speak(normalizedText, correlationId);
      return;
    }

    try {
      await _ensureConfigured(correlationId);
      if (_usingFallback) {
        await _fallback.speak(normalizedText, correlationId);
        return;
      }

      final claimed = await _audioOutputGuard.beginAudioOutput(
        ownerId: _ownerId,
        reason: 'tts_speak_started',
      );
      if (!claimed) {
        eventBus.publish(
          VoiceSystemDegradedEvent(
            source: 'flutter_tts_engine',
            reason: 'tts_audio_output_unavailable',
            correlationId: correlationId,
          ),
        );
        return;
      }

      _speaking = true;
      _activeCorrelationId = correlationId;
      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'flutter_tts_engine',
          previousState: 'ttsIdle',
          nextState: 'ttsSpeaking',
          reason: 'tts_flutter_tts_started',
          correlationId: correlationId,
          metadata: {
            'text': normalizedText,
            'language': _selectedLanguage ?? language,
          },
        ),
      );
      await _client.speak(normalizedText);
    } on MissingPluginException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_missing_plugin',
        correlationId: correlationId,
        error: error,
      );
      await _fallback.speak(normalizedText, correlationId);
    } on PlatformException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_platform_failed',
        correlationId: correlationId,
        error: error,
      );
      await _fallback.speak(normalizedText, correlationId);
    } catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_unexpected_failure',
        correlationId: correlationId,
        error: error,
      );
      await _fallback.speak(normalizedText, correlationId);
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    if (_usingFallback) {
      await _fallback.stop();
      return;
    }

    try {
      await _client.stop();
    } on MissingPluginException {
      _usingFallback = true;
      await _fallback.stop();
    } on PlatformException {
      _usingFallback = true;
      await _fallback.stop();
    } finally {
      _releaseAudioOutput(reason: 'tts_stop');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stop();
    await _fallback.dispose();
    _disposed = true;
  }

  Future<void> _ensureConfigured(String correlationId) async {
    _configuration ??= _configure(correlationId);
    await _configuration;
  }

  Future<void> _configure(String correlationId) async {
    try {
      _client.setCompletionHandler(() {
        _releaseAudioOutput(reason: 'tts_completion');
      });
      _client.setCancelHandler(() {
        _releaseAudioOutput(reason: 'tts_cancelled');
      });
      _client.setErrorHandler((message) {
        _releaseAudioOutput(reason: 'tts_error');
        eventBus.publish(
          VoiceSystemDegradedEvent(
            source: 'flutter_tts_engine',
            reason: 'flutter_tts_runtime_error',
            correlationId: _activeCorrelationId ?? correlationId,
            metadata: {'error': message.toString()},
          ),
        );
      });

      await _client.awaitSpeakCompletion(false);

      final selectedLanguage = await _selectLanguage();
      _selectedLanguage = selectedLanguage;
      await _client.setLanguage(selectedLanguage);
      await _client.setSpeechRate(speechRate);
      await _client.setPitch(pitch);
      await _client.setVolume(volume);
    } on MissingPluginException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_missing_plugin',
        correlationId: correlationId,
        error: error,
      );
    } on PlatformException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_init_failed',
        correlationId: correlationId,
        error: error,
      );
    } catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_init_unexpected_failure',
        correlationId: correlationId,
        error: error,
      );
    }
  }

  Future<String> _selectLanguage() async {
    final languages = _languageCandidates(await _client.getLanguages());
    final normalizedLanguages = languages.map((item) => item.toLowerCase());
    if (normalizedLanguages.contains(language.toLowerCase())) {
      return language;
    }
    if (normalizedLanguages.contains(fallbackLanguage.toLowerCase())) {
      return fallbackLanguage;
    }

    final defaultLanguage = languages.isEmpty ? language : languages.first;
    return defaultLanguage;
  }

  List<String> _languageCandidates(dynamic rawLanguages) {
    if (rawLanguages is! Iterable) {
      return <String>[];
    }
    return rawLanguages
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  void _releaseAudioOutput({required String reason}) {
    if (!_speaking) {
      return;
    }
    _speaking = false;
    final correlationId = _activeCorrelationId;
    _activeCorrelationId = null;
    _audioOutputGuard.endAudioOutput(ownerId: _ownerId, reason: reason);
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'flutter_tts_engine',
        previousState: 'ttsSpeaking',
        nextState: 'ttsIdle',
        reason: reason,
        correlationId: correlationId,
      ),
    );
  }

  Future<void> _activateFallback({
    required String reason,
    required String correlationId,
    required Object error,
  }) async {
    _usingFallback = true;
    _releaseAudioOutput(reason: '${reason}_fallback');
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'flutter_tts_engine',
        reason: reason,
        correlationId: correlationId,
        metadata: {'error': error.toString()},
      ),
    );
    await _fallback.stop();
  }
}
