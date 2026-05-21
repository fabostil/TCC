import 'dart:async';

import '../voice_realtime_event.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'runtime_registry.dart';
import 'runtime_recovery_policy.dart';

class VoiceRuntimeEngine {
  VoiceRuntimeEngine({
    VoiceRealtimeEventBus? eventBus,
    VoiceRuntimeRegistry? registry,
    RuntimeRecoveryPolicy? recoveryPolicy,
    this.defaultRecoveryDelay = const Duration(milliseconds: 700),
    this.maxRecoveryAttempts = 3,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       registry = registry ?? VoiceRuntimeRegistry.instance,
       recoveryPolicy =
           recoveryPolicy ??
           RuntimeRecoveryPolicy(
             maxAttempts: maxRecoveryAttempts,
             baseBackoff: defaultRecoveryDelay,
           );

  static final VoiceRuntimeEngine instance = VoiceRuntimeEngine();

  final VoiceRealtimeEventBus eventBus;
  final VoiceRuntimeRegistry registry;
  final RuntimeRecoveryPolicy recoveryPolicy;
  final Duration defaultRecoveryDelay;
  final int maxRecoveryAttempts;

  final Map<String, Timer> _recoveryTimers = {};
  final Map<String, int> _recoveryAttemptsByCorrelation = {};
  final Set<String> _processedSpeechFailureEventIds = {};
  final Set<String> _processedSpeechFailureCorrelations = {};
  StreamSubscription<VoiceRealtimeEvent>? _subscription;
  void Function()? _registryListener;
  bool _started = false;

  bool get isStarted => _started;

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
    await _subscription?.cancel();
    _subscription = null;
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

    if (event is SpeechListeningFailedEvent) {
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

  void _handleSilenceDetected(SilenceDetectedEvent event) {
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
        message: 'Acao de recovery nao foi executada.',
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

  Future<void> dispose() => stop();

  void resetForTesting() {
    for (final timer in _recoveryTimers.values) {
      timer.cancel();
    }
    _recoveryTimers.clear();
    _recoveryAttemptsByCorrelation.clear();
    _processedSpeechFailureEventIds.clear();
    _processedSpeechFailureCorrelations.clear();
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
