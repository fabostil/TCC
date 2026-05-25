import 'package:flutter/services.dart';

import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../stub_text_to_speech_engine.dart';
import '../text_to_speech_engine.dart';

class FlutterTtsEngine implements TextToSpeechEngine {
  FlutterTtsEngine({
    VoiceRealtimeEventBus? eventBus,
    MethodChannel? channel,
    TextToSpeechEngine? fallback,
    this.language = 'pt-BR',
    this.fallbackLanguage = 'pt-PT',
    this.speechRate = 0.5,
    this.pitch = 1.0,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _channel = channel ?? const MethodChannel('flutter_tts'),
       _fallback =
           fallback ??
           StubTextToSpeechEngine(
             eventBus: eventBus ?? VoiceRealtimeEventBus.instance,
           );

  final VoiceRealtimeEventBus eventBus;
  final MethodChannel _channel;
  final TextToSpeechEngine _fallback;
  final String language;
  final String fallbackLanguage;
  final double speechRate;
  final double pitch;

  Future<void>? _configuration;
  var _disposed = false;
  var _usingFallback = false;

  @override
  Future<void> speak(String text, String correlationId) async {
    if (_disposed || text.trim().isEmpty) {
      return;
    }

    await stop();

    if (_usingFallback) {
      await _fallback.speak(text, correlationId);
      return;
    }

    try {
      await _ensureConfigured(correlationId);
      if (_usingFallback) {
        await _fallback.speak(text, correlationId);
        return;
      }
      await _channel.invokeMethod<Object?>('speak', text);
      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'flutter_tts_engine',
          previousState: 'ttsIdle',
          nextState: 'ttsSpeaking',
          reason: 'tts_flutter_tts_spoken',
          correlationId: correlationId,
          metadata: {'text': text, 'language': language},
        ),
      );
    } on MissingPluginException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_missing_plugin',
        correlationId: correlationId,
        error: error,
      );
      await _fallback.speak(text, correlationId);
    } on PlatformException catch (error) {
      await _activateFallback(
        reason: 'flutter_tts_platform_failed',
        correlationId: correlationId,
        error: error,
      );
      await _fallback.speak(text, correlationId);
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
      await _channel.invokeMethod<Object?>('stop');
    } on MissingPluginException {
      _usingFallback = true;
      await _fallback.stop();
    } on PlatformException {
      _usingFallback = true;
      await _fallback.stop();
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
      await _channel.invokeMethod<Object?>('awaitSpeakCompletion', false);
      await _channel.invokeMethod<Object?>('setQueueMode', 0);

      final selectedLanguage = await _selectLanguage();
      await _channel.invokeMethod<Object?>('setLanguage', selectedLanguage);
      await _channel.invokeMethod<Object?>('setSpeechRate', speechRate);
      await _channel.invokeMethod<Object?>('setPitch', pitch);
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
    }
  }

  Future<String> _selectLanguage() async {
    final nativeAvailable = await _isLanguageAvailable(language);
    if (nativeAvailable) {
      return language;
    }

    final fallbackAvailable = await _isLanguageAvailable(fallbackLanguage);
    if (fallbackAvailable) {
      return fallbackLanguage;
    }

    return language;
  }

  Future<bool> _isLanguageAvailable(String value) async {
    final result = await _channel.invokeMethod<Object?>(
      'isLanguageAvailable',
      value,
    );
    return result == true || result == 1 || result == 'true';
  }

  Future<void> _activateFallback({
    required String reason,
    required String correlationId,
    required Object error,
  }) async {
    _usingFallback = true;
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
