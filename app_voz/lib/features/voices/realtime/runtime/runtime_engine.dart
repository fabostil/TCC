import 'dart:async';
import 'dart:developer' as developer;

import '../../../editor/services/audio_recording_capture.dart';
import '../nlu/voice_intent.dart';
import '../nlu/voice_intent_parser.dart';
import '../voice_realtime_event.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import '../stt/protocols/deepgram_streaming_adapter.dart';
import '../stt/streaming_speech_recognizer.dart';
import '../stt/unsupported_speech_recognizer.dart';
import 'runtime_registry.dart';
import 'runtime_recovery_policy.dart';

enum VoiceSessionState { sleeping, listeningCommand, processingCommand }

class VoiceRuntimeEngine {
  VoiceRuntimeEngine({
    VoiceRealtimeEventBus? eventBus,
    VoiceRuntimeRegistry? registry,
    RuntimeRecoveryPolicy? recoveryPolicy,
    StreamingSpeechRecognizer? streamingSpeechRecognizer,
    this.intentParser = const VoiceIntentParser(),
    this.commandCapture,
    bool? useStreamFirstAudio,
    this.defaultRecoveryDelay = const Duration(milliseconds: 700),
    this.maxRecoveryAttempts = 3,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       registry = registry ?? VoiceRuntimeRegistry.instance,
       useStreamFirstAudio = useStreamFirstAudio ?? _streamFirstFromEnvironment,
       streamingSpeechRecognizer =
           streamingSpeechRecognizer ??
           _createDefaultStreamingSpeechRecognizer(
             eventBus ?? VoiceRealtimeEventBus.instance,
             useStreamFirstAudio ?? _streamFirstFromEnvironment,
           ),
       recoveryPolicy =
           recoveryPolicy ??
           RuntimeRecoveryPolicy(
             maxAttempts: maxRecoveryAttempts,
             baseBackoff: defaultRecoveryDelay,
           );

  static final VoiceRuntimeEngine instance = VoiceRuntimeEngine();
  static const bool _streamFirstFromEnvironment = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  final VoiceRealtimeEventBus eventBus;
  final VoiceRuntimeRegistry registry;
  final RuntimeRecoveryPolicy recoveryPolicy;
  final bool useStreamFirstAudio;
  final StreamingSpeechRecognizer streamingSpeechRecognizer;
  final VoiceIntentParser intentParser;
  final AudioRecordingCapture? commandCapture;
  final Duration defaultRecoveryDelay;
  final int maxRecoveryAttempts;

  final Map<String, Timer> _recoveryTimers = {};
  final Map<String, int> _recoveryAttemptsByCorrelation = {};
  final Set<String> _processedSpeechFailureEventIds = {};
  final Set<String> _processedSpeechFailureCorrelations = {};
  StreamSubscription<VoiceRealtimeEvent>? _subscription;
  void Function()? _registryListener;
  bool _started = false;
  bool _streamingRecognizerInitialized = false;
  bool _streamingRecognitionActive = false;
  String? _streamingCorrelationId;
  VoiceSessionState _currentState = VoiceSessionState.sleeping;
  String? _activeHandsFreeCorrelationId;
  String? _activeHandsFreeOwnerId;

  bool get isStarted => _started;
  VoiceSessionState get currentState => _currentState;

  static StreamingSpeechRecognizer _createDefaultStreamingSpeechRecognizer(
    VoiceRealtimeEventBus eventBus,
    bool useStreamFirstAudio,
  ) {
    final deepgramEndpoint =
        DeepgramStreamingAdapter.endpointFromConfiguredEnvironment();
    final deepgramApiKey = DeepgramStreamingAdapter.apiKeyFromEnvironment;
    if (useStreamFirstAudio &&
        deepgramApiKey.isNotEmpty &&
        deepgramEndpoint != null) {
      return DeepgramStreamingAdapter(
        apiKey: deepgramApiKey,
        endpoint: deepgramEndpoint,
      ).createRecognizer(eventBus: eventBus);
    }

    return UnsupportedSpeechRecognizer(eventBus: eventBus);
  }

  void start() {
    if (_started) {
      return;
    }
    _subscription = eventBus.stream.listen(_handleEvent);
    _registryListener = _handleRegistryChanged;
    registry.addListener(_registryListener!);
    _started = true;
  }

  Future<void> stop() async {
    for (final timer in _recoveryTimers.values) {
      timer.cancel();
    }
    _recoveryTimers.clear();
    _recoveryAttemptsByCorrelation.clear();
    _processedSpeechFailureEventIds.clear();
    _processedSpeechFailureCorrelations.clear();
    _transitionTo(
      VoiceSessionState.sleeping,
      reason: 'runtime_stopped',
      correlationId: _activeHandsFreeCorrelationId,
    );
    _activeHandsFreeCorrelationId = null;
    _activeHandsFreeOwnerId = null;
    await _subscription?.cancel();
    _subscription = null;
    await _stopStreamingRecognition();
    final registryListener = _registryListener;
    if (registryListener != null) {
      registry.removeListener(registryListener);
      _registryListener = null;
    }
    _started = false;
  }

  void _handleEvent(VoiceRealtimeEvent event) {
    if (eventBus.isChainCancelled(event.correlationId)) {
      return;
    }

    if (event is SilenceDetectedEvent) {
      _handleSilenceDetected(event);
      return;
    }

    if (event is VoiceWakeWordDetectedEvent) {
      unawaited(_handleWakeWordDetected(event));
      return;
    }

    if (event is AudioPipelineCaptureStartedEvent) {
      unawaited(_handleAudioPipelineCaptureStarted(event));
      return;
    }

    if (event is AudioPipelineChunkReceivedEvent) {
      _handleAudioPipelineChunkReceived(event);
      return;
    }

    if (event is AudioPipelineCaptureStoppedEvent ||
        event is AudioPipelineShutdownCompleteEvent) {
      unawaited(_stopStreamingRecognition());
      return;
    }

    if (event is RecordingStoppedEvent) {
      unawaited(_handleRecordingStopped(event));
      return;
    }

    if (event is SpeechResultReceivedEvent && event.isFinal) {
      _handleFinalSpeechResult(event);
      return;
    }

    if (event is SpeechListeningFailedEvent) {
      _completeHandsFreeCycle(event, reason: 'speech_listening_failed');
      _handleSpeechListeningFailed(event);
      return;
    }

    if (event is SpeechListeningStartedEvent ||
        event is VoiceSessionRecoveredEvent) {
      recoveryPolicy.reset();
      return;
    }

    if (event is StopVoiceCaptureRequestedEvent) {
      _handleStopVoiceCaptureRequested(event);
      return;
    }

    if (event is RecoverVoiceSessionRequestedEvent) {
      _handleRecoverRequested(event);
    }
  }

  Future<void> _handleWakeWordDetected(VoiceWakeWordDetectedEvent event) async {
    if (!useStreamFirstAudio || _currentState != VoiceSessionState.sleeping) {
      return;
    }

    _activeHandsFreeCorrelationId = event.correlationId;
    _activeHandsFreeOwnerId = event.ownerId;
    _transitionTo(
      VoiceSessionState.listeningCommand,
      reason: 'wake_word_detected',
      correlationId: event.correlationId,
      causationId: event.id,
      ownerId: event.ownerId,
      metadata: event.metadata,
    );

    final requested = StartVoiceCaptureRequestedEvent(
      source: 'runtime_engine',
      ownerId: event.ownerId,
      reason: 'wake_word_detected',
      correlationId: event.correlationId,
      causationId: event.id,
      metadata: event.metadata,
    );
    eventBus.publish(requested);

    final capture = commandCapture;
    if (capture == null) {
      return;
    }

    try {
      final path = await capture.startRecording();
      eventBus.publish(
        RecordingStartedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId,
          reason: 'wake_word_capture_started',
          correlationId: event.correlationId,
          causationId: requested.id,
          metadata: {'path': path},
        ),
      );
    } catch (error) {
      eventBus.publish(
        SpeechListeningFailedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId,
          reason: 'wake_word_capture_start_failed',
          message: 'Falha ao iniciar captura hands-free: $error',
          correlationId: event.correlationId,
          causationId: requested.id,
        ),
      );
    }
  }

  void _handleStopVoiceCaptureRequested(StopVoiceCaptureRequestedEvent event) {
    if (registry.canMutate(source: event.source, ownerId: event.ownerId)) {
      return;
    }

    eventBus.publish(
      StopVoiceCaptureRejectedEvent(
        source: 'runtime_engine',
        ownerId: event.ownerId,
        reason: 'ownership_required',
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'eventSource': event.source,
          'activeOwnerId': registry.ownership.ownerId,
        },
      ),
    );
  }

  Future<void> _handleAudioPipelineCaptureStarted(
    AudioPipelineCaptureStartedEvent event,
  ) async {
    if (!useStreamFirstAudio) {
      return;
    }
    if (_currentState == VoiceSessionState.listeningCommand) {
      return;
    }
    await _ensureStreamingRecognizerInitialized();
    await streamingSpeechRecognizer.startRecognition(event.correlationId);
    _streamingRecognitionActive = true;
    _streamingCorrelationId = event.correlationId;
  }

  void _handleAudioPipelineChunkReceived(
    AudioPipelineChunkReceivedEvent event,
  ) {
    if (!useStreamFirstAudio || !_streamingRecognitionActive) {
      return;
    }
    if (_streamingCorrelationId != event.correlationId) {
      return;
    }
    streamingSpeechRecognizer.feedAudioChunk(event.chunk);
  }

  Future<void> _ensureStreamingRecognizerInitialized() async {
    if (_streamingRecognizerInitialized) {
      return;
    }
    await streamingSpeechRecognizer.initializeRecognizer();
    _streamingRecognizerInitialized = true;
  }

  Future<void> _stopStreamingRecognition() async {
    if (!_streamingRecognitionActive) {
      return;
    }
    _streamingRecognitionActive = false;
    _streamingCorrelationId = null;
    await streamingSpeechRecognizer.stopRecognition();
  }

  void _handleSilenceDetected(SilenceDetectedEvent event) {
    if (!_shouldProcessSilence(event)) {
      return;
    }

    if (useStreamFirstAudio) {
      unawaited(_handleHandsFreeSilenceDetected(event));
      return;
    }

    final session = registry.activeVoiceSession;
    if (session == null) {
      eventBus.publish(
        RecoverySkippedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId,
          reason: 'no_active_voice_session',
          correlationId: event.correlationId,
          causationId: event.id,
          message: 'Silencio detectado sem sessao de voz ativa.',
        ),
      );
      return;
    }

    eventBus.publish(
      StopVoiceCaptureRequestedEvent(
        source: 'runtime_engine',
        ownerId: session.ownerId,
        reason: 'silence_detected',
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'sessionToken': session.token,
          'routeId': session.routeId,
          ...event.metadata,
        },
      ),
    );

    eventBus.publish(
      RecoverVoiceSessionRequestedEvent(
        source: 'runtime_engine',
        ownerId: session.ownerId,
        reason: 'after_silence_detected',
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'sessionToken': session.token,
          'routeId': session.routeId,
          ...event.metadata,
        },
      ),
    );
  }

  Future<void> _handleHandsFreeSilenceDetected(
    SilenceDetectedEvent event,
  ) async {
    if (_currentState != VoiceSessionState.listeningCommand) {
      return;
    }
    if (_activeHandsFreeCorrelationId != event.correlationId) {
      return;
    }

    _transitionTo(
      VoiceSessionState.processingCommand,
      reason: 'isolate_silence_detected',
      correlationId: event.correlationId,
      causationId: event.id,
      ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
      metadata: event.metadata,
    );

    final stop = StopVoiceCaptureRequestedEvent(
      source: 'runtime_engine',
      ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
      reason: 'isolate_silence_detected',
      correlationId: event.correlationId,
      causationId: event.id,
      metadata: event.metadata,
    );
    eventBus.publish(stop);

    final capture = commandCapture;
    if (capture == null) {
      return;
    }

    try {
      final path = await capture.stopRecording();
      eventBus.publish(
        RecordingStoppedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
          reason: 'hands_free_command_file_ready',
          correlationId: event.correlationId,
          causationId: stop.id,
          metadata: {
            'path': ?path,
            'fileReady': path != null && path.isNotEmpty,
          },
        ),
      );
    } catch (error) {
      eventBus.publish(
        SpeechListeningFailedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
          reason: 'hands_free_capture_stop_failed',
          message: 'Falha ao fechar captura hands-free: $error',
          correlationId: event.correlationId,
          causationId: stop.id,
        ),
      );
    }
  }

  Future<void> _handleRecordingStopped(RecordingStoppedEvent event) async {
    if (!useStreamFirstAudio ||
        _currentState != VoiceSessionState.processingCommand ||
        _activeHandsFreeCorrelationId != event.correlationId) {
      return;
    }

    await _ensureStreamingRecognizerInitialized();
    await streamingSpeechRecognizer.startRecognition(event.correlationId);
    _streamingRecognitionActive = true;
    _streamingCorrelationId = event.correlationId;
  }

  bool _shouldProcessSilence(SilenceDetectedEvent event) {
    return useStreamFirstAudio ? event.isIsolateEngine : !event.isIsolateEngine;
  }

  void _handleFinalSpeechResult(SpeechResultReceivedEvent event) {
    developer.log(
      "[STT_DEBUG] TEXTO RECEBIDO: '${event.text}'",
      name: 'VoiceRuntimeEngine',
    );

    if (useStreamFirstAudio &&
        _streamingRecognitionActive &&
        _streamingCorrelationId == event.correlationId &&
        _currentState == VoiceSessionState.sleeping) {
      _publishStreamingIntent(event);
      return;
    }

    if (!useStreamFirstAudio ||
        _currentState != VoiceSessionState.processingCommand ||
        _activeHandsFreeCorrelationId != event.correlationId) {
      return;
    }

    final intent = intentParser.parse(event.text);
    eventBus.publish(
      VoiceCommandInterpretedEvent(
        source: 'runtime_engine',
        ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
        reason: 'speech_result_received',
        correlationId: event.correlationId,
        causationId: event.id,
        intent: intent,
      ),
    );

    _completeHandsFreeCycle(
      event,
      reason: intent is UnknownIntent
          ? 'unknown_voice_intent'
          : 'voice_intent_interpreted',
    );
  }

  void _publishStreamingIntent(SpeechResultReceivedEvent event) {
    final intent = intentParser.parse(event.text);
    eventBus.publish(
      VoiceCommandInterpretedEvent(
        source: 'runtime_engine',
        ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
        reason: 'streaming_speech_result_received',
        correlationId: event.correlationId,
        causationId: event.id,
        intent: intent,
      ),
    );
  }

  void _completeHandsFreeCycle(
    VoiceRealtimeEvent event, {
    required String reason,
  }) {
    if (!useStreamFirstAudio ||
        _currentState != VoiceSessionState.processingCommand ||
        _activeHandsFreeCorrelationId != event.correlationId) {
      return;
    }

    _transitionTo(
      VoiceSessionState.sleeping,
      reason: reason,
      correlationId: event.correlationId,
      causationId: event.id,
      ownerId: event.ownerId ?? _activeHandsFreeOwnerId,
      metadata: event.metadata,
    );
    _activeHandsFreeCorrelationId = null;
    _activeHandsFreeOwnerId = null;
    unawaited(_stopStreamingRecognition());
  }

  void _transitionTo(
    VoiceSessionState next, {
    required String reason,
    String? correlationId,
    String? causationId,
    String? ownerId,
    Map<String, Object?> metadata = const {},
  }) {
    final previous = _currentState;
    if (previous == next) {
      return;
    }

    _currentState = next;
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'runtime_engine',
        ownerId: ownerId ?? _activeHandsFreeOwnerId,
        previousState: previous.name,
        nextState: next.name,
        reason: reason,
        correlationId: correlationId ?? _activeHandsFreeCorrelationId,
        causationId: causationId,
        metadata: {
          'sessionState': next.name,
          'previousSessionState': previous.name,
          ...metadata,
        },
      ),
    );
  }

  void _handleSpeechListeningFailed(SpeechListeningFailedEvent event) {
    if (!_markSpeechFailureProcessed(event)) {
      return;
    }

    final session = registry.activeVoiceSession;
    if (session == null) {
      eventBus.publish(
        RecoverySkippedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId,
          reason: 'no_active_voice_session',
          correlationId: event.correlationId,
          causationId: event.id,
          message: 'Falha STT sem sessao ativa para recovery.',
        ),
      );
      return;
    }

    if (!recoveryPolicy.shouldAttemptRecovery()) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'runtime_engine',
          ownerId: event.ownerId ?? session.ownerId,
          reason: 'recovery_budget_exhausted',
          correlationId: event.correlationId,
          causationId: event.id,
          metadata: {
            'maxAttempts': recoveryPolicy.maxAttempts,
            'consecutiveFailures': recoveryPolicy.consecutiveFailures,
            'contextSnapshot': registry.snapshotMetadata(),
          },
        ),
      );
      registry.clearVoiceSession(
        ownerId: session.ownerId,
        token: session.token,
      );
      return;
    }

    final attempt = recoveryPolicy.nextAttemptNumber;
    final backoff = recoveryPolicy.nextBackoff();
    recoveryPolicy.recordFailure();
    final contextSnapshot = registry.snapshotMetadata();
    eventBus.publish(
      VoiceRecoveryRetryingEvent(
        source: 'runtime_engine',
        ownerId: session.ownerId,
        reason: 'after_speech_failure',
        correlationId: event.correlationId,
        causationId: event.id,
        attempt: attempt,
        delayMs: backoff.inMilliseconds,
        metadata: {
          'sessionToken': session.token,
          'failureReason': event.reason,
          'contextSnapshot': contextSnapshot,
        },
      ),
    );

    eventBus.publish(
      RecoverVoiceSessionRequestedEvent(
        source: 'runtime_engine',
        ownerId: session.ownerId,
        reason: 'after_speech_failure',
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'sessionToken': session.token,
          'routeId': session.routeId,
          'failureReason': event.reason,
          'delayMs': backoff.inMilliseconds,
          'attempt': attempt,
          'contextSnapshot': contextSnapshot,
        },
      ),
    );
  }

  void _handleRegistryChanged() {
    final routeContext = registry.activeRouteContext;
    final session = registry.activeVoiceSession;
    if (session == null || routeContext == null) {
      return;
    }

    final allowed = routeContext.metadata['voiceRuntimeAllowed'];
    if (allowed != false) {
      return;
    }

    final correlationId =
        'route_guard_${routeContext.routeId}_${session.token}';
    eventBus.publish(
      StopVoiceCaptureRequestedEvent(
        source: 'runtime_engine',
        ownerId: session.ownerId,
        reason: 'route_out_of_scope',
        correlationId: correlationId,
        metadata: {
          'sessionToken': session.token,
          'routeId': routeContext.routeId,
          'routeName': routeContext.routeName,
        },
      ),
    );
    registry.clearVoiceSession(ownerId: session.ownerId, token: session.token);
  }

  void _handleRecoverRequested(RecoverVoiceSessionRequestedEvent event) {
    final session = registry.activeVoiceSession;
    final ownerId = event.ownerId ?? session?.ownerId;
    final sessionToken = _sessionTokenFrom(event) ?? session?.token;

    if (ownerId == null || sessionToken == null) {
      _publishRecoverySkipped(
        event,
        reason: 'no_active_voice_session',
        message: 'Recovery solicitado sem sessao ativa.',
      );
      return;
    }

    if (!registry.isVoiceSessionActive(ownerId: ownerId, token: sessionToken)) {
      _publishRecoverySkipped(
        event,
        reason: 'stale_voice_session',
        message: 'Recovery ignorado para sessao obsoleta.',
      );
      return;
    }

    final attempts =
        _recoveryAttemptsByCorrelation[event.correlationId] ??
        _attemptsFrom(event);
    if (attempts >= maxRecoveryAttempts) {
      _publishRecoverySkipped(
        event,
        reason: 'max_attempts',
        message: 'Recovery ignorado apos $attempts tentativas.',
        metadata: {'attempts': attempts},
      );
      return;
    }

    final delay = _delayFrom(event);
    _recoveryTimers[event.correlationId]?.cancel();
    eventBus.publish(
      RecoveryScheduledEvent(
        source: 'runtime_engine',
        ownerId: ownerId,
        reason: event.reason,
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {
          'delayMs': delay.inMilliseconds,
          'attempts': attempts,
          'sessionToken': sessionToken,
        },
      ),
    );

    _recoveryTimers[event.correlationId] = Timer(delay, () async {
      await _attemptRecovery(event, ownerId, sessionToken, attempts);
    });
  }

  Future<void> _attemptRecovery(
    RecoverVoiceSessionRequestedEvent request,
    String ownerId,
    int sessionToken,
    int attempts,
  ) async {
    _recoveryTimers.remove(request.correlationId);

    if (eventBus.isChainCancelled(request.correlationId)) {
      return;
    }

    if (!registry.canRecoverVoiceSession(
      ownerId: ownerId,
      token: sessionToken,
    )) {
      _publishRecoverySkipped(
        request,
        reason: 'condition_false',
        message: 'Recovery cancelado por condicao atual.',
        metadata: {'sessionToken': sessionToken},
      );
      return;
    }

    final nextAttempts = attempts + 1;
    _recoveryAttemptsByCorrelation[request.correlationId] = nextAttempts;
    final attempted = RecoveryAttemptedEvent(
      source: 'runtime_engine',
      ownerId: ownerId,
      reason: request.reason,
      correlationId: request.correlationId,
      causationId: request.id,
      metadata: {'attempts': nextAttempts, 'sessionToken': sessionToken},
    );
    eventBus.publish(attempted);

    final recovered = await registry.recoverVoiceSession(
      ownerId: ownerId,
      token: sessionToken,
    );
    if (!recovered) {
      _publishRecoverySkipped(
        request,
        reason: 'recover_action_rejected',
        message: 'Ação de recuperação não foi executada.',
        metadata: {'sessionToken': sessionToken},
      );
      return;
    }

    eventBus.publish(
      VoiceSessionRecoveredEvent(
        source: 'runtime_engine',
        ownerId: ownerId,
        reason: request.reason,
        correlationId: request.correlationId,
        causationId: attempted.id,
      ),
    );
  }

  void _publishRecoverySkipped(
    RecoverVoiceSessionRequestedEvent event, {
    required String reason,
    required String message,
    Map<String, Object?> metadata = const {},
  }) {
    eventBus.publish(
      RecoverySkippedEvent(
        source: 'runtime_engine',
        ownerId: event.ownerId,
        reason: reason,
        correlationId: event.correlationId,
        causationId: event.id,
        message: message,
        metadata: metadata,
      ),
    );
  }

  int _attemptsFrom(RecoverVoiceSessionRequestedEvent event) {
    final value = event.metadata['attempts'];
    return value is int ? value : 0;
  }

  Duration _delayFrom(RecoverVoiceSessionRequestedEvent event) {
    final value = event.metadata['delayMs'];
    return value is int ? Duration(milliseconds: value) : defaultRecoveryDelay;
  }

  int? _sessionTokenFrom(RecoverVoiceSessionRequestedEvent event) {
    final value = event.metadata['sessionToken'];
    return value is int ? value : null;
  }

  Future<void> dispose() async {
    await stop();
    await streamingSpeechRecognizer.dispose();
  }

  void resetForTesting() {
    for (final timer in _recoveryTimers.values) {
      timer.cancel();
    }
    _recoveryTimers.clear();
    _recoveryAttemptsByCorrelation.clear();
    _processedSpeechFailureEventIds.clear();
    _processedSpeechFailureCorrelations.clear();
    _currentState = VoiceSessionState.sleeping;
    _activeHandsFreeCorrelationId = null;
    _activeHandsFreeOwnerId = null;
    recoveryPolicy.reset();
  }

  bool _markSpeechFailureProcessed(SpeechListeningFailedEvent event) {
    if (_processedSpeechFailureEventIds.contains(event.id) ||
        _processedSpeechFailureCorrelations.contains(event.correlationId)) {
      return false;
    }
    _processedSpeechFailureEventIds.add(event.id);
    _processedSpeechFailureCorrelations.add(event.correlationId);
    return true;
  }
}
