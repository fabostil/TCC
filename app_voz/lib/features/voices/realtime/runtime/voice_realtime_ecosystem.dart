import 'dart:async';

import '../dispatch/voice_command_dispatcher.dart';
import '../infrastructure/service/stub_voice_foreground_service.dart';
import '../infrastructure/service/voice_foreground_service.dart';
import '../tts/voice_response_bridge.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'runtime_engine.dart';

class VoiceRealtimeEcosystem {
  VoiceRealtimeEcosystem({
    VoiceRuntimeEngine? runtimeEngine,
    VoiceResponseBridge? responseBridge,
    VoiceCommandDispatcher? commandDispatcher,
    VoiceForegroundService? foregroundService,
    VoiceRealtimeEventBus? eventBus,
    bool? useStreamFirstAudio,
  }) : runtimeEngine = runtimeEngine ?? VoiceRuntimeEngine.instance,
       responseBridge = responseBridge ?? VoiceResponseBridge.instance,
       commandDispatcher = commandDispatcher ?? VoiceCommandDispatcher.instance,
       eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       useStreamFirstAudio = useStreamFirstAudio ?? _streamFirstFromEnvironment,
       foregroundService =
           foregroundService ??
           StubVoiceForegroundService(
             eventBus: eventBus ?? VoiceRealtimeEventBus.instance,
           );

  static final VoiceRealtimeEcosystem instance = VoiceRealtimeEcosystem();

  static const bool _streamFirstFromEnvironment = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  static const String foregroundTitle = 'Assistente Musical Ativo';
  static const String foregroundMessage = 'Escuta hands-free ligada';

  final VoiceRuntimeEngine runtimeEngine;
  final VoiceResponseBridge responseBridge;
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
