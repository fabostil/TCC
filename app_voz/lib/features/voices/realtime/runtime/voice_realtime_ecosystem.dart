import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dispatch/voice_command_dispatcher.dart';
import '../dispatch/contracts/voice_session_context_holder.dart';
import '../dispatch/handlers/metronome_command_handler.dart';
import '../../../metronome/services/metronome_service_impl.dart';
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
    MetronomeService? metronomeService,
    VoiceForegroundService? foregroundService,
    VoiceRealtimeEventBus? eventBus,
    bool? useStreamFirstAudio,
  }) {
    final resolvedEventBus = eventBus ?? VoiceRealtimeEventBus.instance;
    final resolvedContextHolder =
        sessionContextHolder ?? VoiceSessionContextHolder();
    final sessionTokenController = _VoiceRealtimeSessionTokenController();
    final resolvedMetronomeService = metronomeService ?? MetronomeServiceImpl();

    return VoiceRealtimeEcosystem._(
      runtimeEngine: runtimeEngine ?? VoiceRuntimeEngine.instance,
      sessionContextHolder: resolvedContextHolder,
      sessionTokenController: sessionTokenController,
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
            activeSessionTokenProvider: () =>
                sessionTokenController.activeSessionToken,
            metronomeService: resolvedMetronomeService,
          ),
      metronomeService: resolvedMetronomeService,
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
    required _VoiceRealtimeSessionTokenController sessionTokenController,
    required this.commandDispatcher,
    required this.metronomeService,
    required this.foregroundService,
    required this.eventBus,
    required this.useStreamFirstAudio,
  }) : _sessionTokenController = sessionTokenController;

  static final VoiceRealtimeEcosystem instance = VoiceRealtimeEcosystem();

  static const bool _streamFirstFromEnvironment = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  static TextToSpeechEngine _createDefaultTtsEngine({
    required VoiceRealtimeEventBus eventBus,
  }) {
    try {
      return FlutterTtsEngine(eventBus: eventBus);
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: 'tts_engine_initialization_failed',
          correlationId: 'tts_engine',
          metadata: {'error': error.toString()},
        ),
      );
      return StubTextToSpeechEngine(eventBus: eventBus);
    }
  }

  static VoiceForegroundService _createDefaultForegroundService({
    required VoiceRealtimeEventBus eventBus,
  }) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return StubVoiceForegroundService(eventBus: eventBus);
    }

    try {
      return AndroidVoiceForegroundService(eventBus: eventBus);
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: 'foreground_service_initialization_failed',
          correlationId: 'foreground_service',
          metadata: {'error': error.toString()},
        ),
      );
      return StubVoiceForegroundService(eventBus: eventBus);
    }
  }

  static const String foregroundTitle =
      AndroidVoiceForegroundService.notificationTitle;
  static const String foregroundMessage =
      AndroidVoiceForegroundService.notificationMessage;

  final VoiceRuntimeEngine runtimeEngine;
  final VoiceResponseBridge responseBridge;
  final VoiceSessionContextHolder sessionContextHolder;
  final VoiceCommandDispatcher commandDispatcher;
  final MetronomeService metronomeService;
  final VoiceForegroundService foregroundService;
  final VoiceRealtimeEventBus eventBus;
  final bool useStreamFirstAudio;
  final _VoiceRealtimeSessionTokenController _sessionTokenController;

  var _started = false;
  var _foregroundStarted = false;
  Future<void>? _shutdownInFlight;
  StreamSubscription<RecordingStartedEvent>? _recordingStartedSubscription;

  bool get isStarted => _started;
  bool get isForegroundStarted => _foregroundStarted;
  String? get activeSessionToken => _sessionTokenController.activeSessionToken;

  void updateActiveContext({
    String? projectId,
    String? userId,
    String? sessionToken,
  }) {
    _sessionTokenController.activeSessionToken = sessionToken;
    sessionContextHolder.updateActiveContext(
      projectId: projectId,
      userId: userId,
      sessionToken: sessionToken,
    );
  }

  void clearActiveContext() {
    _sessionTokenController.activeSessionToken = null;
    sessionContextHolder.clearActiveContext();
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    runtimeEngine.start();
    responseBridge.start();
    commandDispatcher.start();
    _recordingStartedSubscription ??= eventBus
        .on<RecordingStartedEvent>()
        .listen(_handleRecordingStarted);

    if (!useStreamFirstAudio) {
      return;
    }

    try {
      await foregroundService.startService(
        title: foregroundTitle,
        message: foregroundMessage,
      );
      final foreground = foregroundService;
      if (foreground is AndroidVoiceForegroundService &&
          !foreground.isStarted) {
        return;
      }
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
      clearActiveContext();
      commandDispatcher.clearPendingTransaction(reason: 'realtime_stopped');
      return;
    }
    _started = false;
    clearActiveContext();
    commandDispatcher.clearPendingTransaction(reason: 'realtime_stopped');
    await _recordingStartedSubscription?.cancel();
    _recordingStartedSubscription = null;

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

  Future<void> shutdown({String reason = 'shutdown'}) {
    final inFlight = _shutdownInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _shutdown(reason).whenComplete(() {
      _shutdownInFlight = null;
    });
    _shutdownInFlight = future;
    return future;
  }

  void startUnawaited() {
    unawaited(start());
  }

  Future<void> _shutdown(String reason) async {
    _started = false;
    clearActiveContext();
    commandDispatcher.clearPendingTransaction(reason: reason);

    try {
      await _recordingStartedSubscription?.cancel();
    } catch (_) {
      // Shutdown must stay idempotent and best-effort.
    } finally {
      _recordingStartedSubscription = null;
    }

    try {
      await foregroundService.stopService();
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: 'foreground_service_shutdown_failed',
          correlationId: 'foreground_service',
          metadata: {'error': error.toString(), 'shutdownReason': reason},
        ),
      );
    } finally {
      _foregroundStarted = false;
    }

    await Future.wait<void>([
      _disposeIgnoringFailure(commandDispatcher.dispose, 'dispatcher', reason),
      _disposeIgnoringFailure(
        responseBridge.dispose,
        'response_bridge',
        reason,
      ),
      _disposeIgnoringFailure(runtimeEngine.dispose, 'runtime_engine', reason),
      _disposeIgnoringFailure(metronomeService.dispose, 'metronome', reason),
    ]);

    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_realtime_ecosystem',
        previousState: 'running',
        nextState: 'shutdown',
        reason: reason,
      ),
    );
  }

  Future<void> _disposeIgnoringFailure(
    Future<void> Function() dispose,
    String component,
    String reason,
  ) async {
    try {
      await dispose();
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_realtime_ecosystem',
          reason: '${component}_shutdown_failed',
          metadata: {'error': error.toString(), 'shutdownReason': reason},
        ),
      );
    }
  }

  void _handleRecordingStarted(RecordingStartedEvent event) {
    unawaited(_stopMetronomeForRecording(event));
  }

  Future<void> _stopMetronomeForRecording(RecordingStartedEvent event) async {
    final wasRunning = metronomeService.isRunning;
    await metronomeService.stop();
    if (!wasRunning) {
      return;
    }
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_realtime_ecosystem',
        previousState: 'metronomeRunning',
        nextState: 'metronomeStopped',
        reason: 'metronome_stopped_for_recording',
        ownerId: event.ownerId,
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'recordingSource': event.source,
          'recordingReason': event.reason,
        },
      ),
    );
  }
}

class _VoiceRealtimeSessionTokenController {
  String? activeSessionToken;
}
