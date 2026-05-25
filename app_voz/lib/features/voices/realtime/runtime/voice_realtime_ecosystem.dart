import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dispatch/voice_command_dispatcher.dart';
import '../dispatch/contracts/voice_session_context_holder.dart';
import '../infrastructure/service/android_voice_foreground_service.dart';
import '../infrastructure/service/stub_voice_foreground_service.dart';
import '../infrastructure/service/voice_foreground_service.dart';
import '../tts/adapters/flutter_tts_engine.dart';
import '../tts/stub_text_to_speech_engine.dart';
import '../tts/text_to_speech_engine.dart';
import '../tts/voice_response_bridge.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'runtime_engine.dart';

class VoiceRealtimeEcosystem {
  factory VoiceRealtimeEcosystem({
    VoiceRuntimeEngine? runtimeEngine,
    VoiceResponseBridge? responseBridge,
    TextToSpeechEngine? ttsEngine,
    VoiceSessionContextHolder? sessionContextHolder,
    VoiceCommandDispatcher? commandDispatcher,
    VoiceForegroundService? foregroundService,
    VoiceRealtimeEventBus? eventBus,
    bool? useStreamFirstAudio,
  }) {
    final resolvedEventBus = eventBus ?? VoiceRealtimeEventBus.instance;
    final resolvedContextHolder =
        sessionContextHolder ?? VoiceSessionContextHolder();

    return VoiceRealtimeEcosystem._(
      runtimeEngine: runtimeEngine ?? VoiceRuntimeEngine.instance,
      sessionContextHolder: resolvedContextHolder,
      responseBridge:
          responseBridge ??
          VoiceResponseBridge(
            eventBus: resolvedEventBus,
            ttsEngine:
                ttsEngine ??
                _createDefaultTtsEngine(eventBus: resolvedEventBus),
          ),
      commandDispatcher:
          commandDispatcher ??
          VoiceCommandDispatcher(
            eventBus: resolvedEventBus,
            contextHolder: resolvedContextHolder,
          ),
      eventBus: resolvedEventBus,
      useStreamFirstAudio: useStreamFirstAudio ?? _streamFirstFromEnvironment,
      foregroundService:
          foregroundService ??
          _createDefaultForegroundService(eventBus: resolvedEventBus),
    );
  }

  VoiceRealtimeEcosystem._({
    required this.runtimeEngine,
    required this.responseBridge,
    required this.sessionContextHolder,
    required this.commandDispatcher,
    required this.foregroundService,
    required this.eventBus,
    required this.useStreamFirstAudio,
  });

  static final VoiceRealtimeEcosystem instance = VoiceRealtimeEcosystem();

  static const bool _streamFirstFromEnvironment = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  static TextToSpeechEngine _createDefaultTtsEngine({
    required VoiceRealtimeEventBus eventBus,
  }) {
    if (kReleaseMode) {
      return FlutterTtsEngine(eventBus: eventBus);
    }

    return StubTextToSpeechEngine(eventBus: eventBus);
  }

  static VoiceForegroundService _createDefaultForegroundService({
    required VoiceRealtimeEventBus eventBus,
  }) {
    if (kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidVoiceForegroundService(eventBus: eventBus);
    }

    return StubVoiceForegroundService(eventBus: eventBus);
  }

  static const String foregroundTitle =
      AndroidVoiceForegroundService.notificationTitle;
  static const String foregroundMessage =
      AndroidVoiceForegroundService.notificationMessage;

  final VoiceRuntimeEngine runtimeEngine;
  final VoiceResponseBridge responseBridge;
  final VoiceSessionContextHolder sessionContextHolder;
  final VoiceCommandDispatcher commandDispatcher;
  final VoiceForegroundService foregroundService;
  final VoiceRealtimeEventBus eventBus;
  final bool useStreamFirstAudio;

  var _started = false;
  var _foregroundStarted = false;

  bool get isStarted => _started;
  bool get isForegroundStarted => _foregroundStarted;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    runtimeEngine.start();
    responseBridge.start();
    commandDispatcher.start();

    if (!useStreamFirstAudio) {
      return;
    }

    try {
      await foregroundService.startService(
        title: foregroundTitle,
        message: foregroundMessage,
      );
      _foregroundStarted = true;
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: 'foreground_service_start_failed',
          correlationId: 'foreground_service',
          metadata: {'error': error.toString()},
        ),
      );
    }
  }

  Future<void> updateForegroundMessage(String message) async {
    if (!useStreamFirstAudio || !_foregroundStarted) {
      return;
    }

    try {
      await foregroundService.updateMessage(message);
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: 'foreground_service_update_failed',
          correlationId: 'foreground_service',
          metadata: {'error': error.toString()},
        ),
      );
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    sessionContextHolder.updateActiveContext();
    commandDispatcher.clearPendingTransaction(reason: 'realtime_stopped');

    if (useStreamFirstAudio && _foregroundStarted) {
      try {
        await foregroundService.stopService();
      } catch (error) {
        eventBus.publish(
          VoiceSystemDegradedEvent(
            source: 'voice_realtime_ecosystem',
            reason: 'foreground_service_stop_failed',
            correlationId: 'foreground_service',
            metadata: {'error': error.toString()},
          ),
        );
      } finally {
        _foregroundStarted = false;
      }
    }
  }

  void startUnawaited() {
    unawaited(start());
  }
}
