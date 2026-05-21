// ignore_for_file: use_super_parameters

import 'voice_realtime_event.dart';

class AudioOwnershipChangedEvent extends VoiceRealtimeEvent {
  AudioOwnershipChangedEvent({
    required String source,
    required String from,
    required String to,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.audioOwnershipChanged,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Ownership de audio alterado: $from -> $to.',
         metadata: {'from': from, 'to': to},
       );
}

class AudioPipelineReadyEvent extends VoiceRealtimeEvent {
  AudioPipelineReadyEvent({
    required String source,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineReady,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline isolate pronto.',
         metadata: metadata,
       );
}

class AudioPipelineCaptureStartedEvent extends VoiceRealtimeEvent {
  AudioPipelineCaptureStartedEvent({
    required String source,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineCaptureStarted,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline iniciou captura simulada.',
         metadata: metadata,
       );
}

class AudioPipelineCaptureStoppedEvent extends VoiceRealtimeEvent {
  AudioPipelineCaptureStoppedEvent({
    required String source,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineCaptureStopped,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline encerrou captura simulada.',
         metadata: metadata,
       );
}

class AudioPipelinePongEvent extends VoiceRealtimeEvent {
  AudioPipelinePongEvent({
    required String source,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelinePong,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline respondeu PING.',
         metadata: metadata,
       );
}

class AudioPipelineShutdownCompleteEvent extends VoiceRealtimeEvent {
  AudioPipelineShutdownCompleteEvent({
    required String source,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineShutdownComplete,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline finalizou shutdown.',
         metadata: metadata,
       );
}

class AudioPipelineErrorEvent extends VoiceRealtimeEvent {
  AudioPipelineErrorEvent({
    required String source,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineError,
         source: source,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Audio pipeline reportou erro.',
         severity: VoiceRealtimeEventSeverity.warning,
         metadata: metadata,
       );
}

class EventChainCancelledEvent extends VoiceRealtimeEvent {
  EventChainCancelledEvent({
    required String source,
    required String cancelledCorrelationId,
    String? ownerId,
    String? reason,
    String? message,
  }) : super(
         type: VoiceRealtimeEventType.eventChainCancelled,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: cancelledCorrelationId,
         message: message ?? 'Cadeia de eventos cancelada.',
         metadata: {'cancelledCorrelationId': cancelledCorrelationId},
       );
}

class MicrophoneConflictDetectedEvent extends VoiceRealtimeEvent {
  MicrophoneConflictDetectedEvent({
    required String source,
    required String conflict,
    String? ownerId,
    String? reason,
    String? message,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.microphoneConflictDetected,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: message ?? 'Conflito de microfone detectado.',
         severity: VoiceRealtimeEventSeverity.warning,
         metadata: {'conflict': conflict},
       );
}

class PlaybackStartedEvent extends VoiceRealtimeEvent {
  PlaybackStartedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.playbackStarted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Playback iniciado.',
       );
}

class PlaybackStoppedEvent extends VoiceRealtimeEvent {
  PlaybackStoppedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.playbackStopped,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Playback encerrado.',
       );
}

class RecoverVoiceSessionRequestedEvent extends VoiceRealtimeEvent {
  RecoverVoiceSessionRequestedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recoverVoiceSessionRequested,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Recovery de sessao solicitado.',
         cancelable: true,
         metadata: metadata,
       );
}

class RecordingPausedEvent extends VoiceRealtimeEvent {
  RecordingPausedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.recordingPaused,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Gravacao pausada.',
       );
}

class RecordingResumedEvent extends VoiceRealtimeEvent {
  RecordingResumedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.recordingResumed,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Gravacao retomada.',
       );
}

class RecordingStartedEvent extends VoiceRealtimeEvent {
  RecordingStartedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recordingStarted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Gravacao iniciada.',
         metadata: metadata,
       );
}

class RecordingStoppedEvent extends VoiceRealtimeEvent {
  RecordingStoppedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recordingStopped,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Gravacao encerrada.',
         metadata: metadata,
       );
}

class RecoveryAttemptedEvent extends VoiceRealtimeEvent {
  RecoveryAttemptedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recoveryAttempted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Tentativa de recovery iniciada.',
         cancelable: true,
         metadata: metadata,
       );
}

class RecoveryScheduledEvent extends VoiceRealtimeEvent {
  RecoveryScheduledEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recoveryScheduled,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Recovery agendado.',
         cancelable: true,
         metadata: metadata,
       );
}

class RecoverySkippedEvent extends VoiceRealtimeEvent {
  RecoverySkippedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    String? message,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.recoverySkipped,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: message ?? 'Recovery ignorado.',
         severity: VoiceRealtimeEventSeverity.warning,
         metadata: metadata,
       );
}

class SilenceDetectedEvent extends VoiceRealtimeEvent {
  SilenceDetectedEvent({
    required String source,
    required int silenceMs,
    required double level,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.silenceDetected,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Silencio detectado.',
         metadata: {'silenceMs': silenceMs, 'level': level},
       );
}

class SpeechListeningFailedEvent extends VoiceRealtimeEvent {
  SpeechListeningFailedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? message,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.speechListeningFailed,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: message ?? 'Falha na escuta STT.',
         severity: VoiceRealtimeEventSeverity.error,
       );
}

class SpeechResultReceivedEvent extends VoiceRealtimeEvent {
  SpeechResultReceivedEvent({
    required String source,
    required String text,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.speechResultReceived,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Resultado STT recebido.',
         metadata: {'text': text},
       );
}

class SpeechListeningStartedEvent extends VoiceRealtimeEvent {
  SpeechListeningStartedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.speechListeningStarted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Escuta STT iniciada.',
       );
}

class SpeechListeningStoppedEvent extends VoiceRealtimeEvent {
  SpeechListeningStoppedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.speechListeningStopped,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Escuta STT encerrada.',
       );
}

class StopVoiceCaptureRequestedEvent extends VoiceRealtimeEvent {
  StopVoiceCaptureRequestedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.stopVoiceCaptureRequested,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Encerramento seguro de captura de voz solicitado.',
         cancelable: true,
         metadata: metadata,
       );
}

class StopVoiceCaptureRejectedEvent extends VoiceRealtimeEvent {
  StopVoiceCaptureRejectedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.stopVoiceCaptureRejected,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Comando de captura rejeitado por ownership invalido.',
         severity: VoiceRealtimeEventSeverity.warning,
         metadata: metadata,
       );
}

class VoiceOwnershipRequestedEvent extends VoiceRealtimeEvent {
  VoiceOwnershipRequestedEvent({
    required String source,
    required String requesterId,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceOwnershipRequested,
         source: source,
         ownerId: ownerId ?? requesterId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Ownership realtime solicitado.',
         cancelable: true,
         metadata: {'requesterId': requesterId, ...metadata},
       );
}

class VoiceOwnershipGrantedEvent extends VoiceRealtimeEvent {
  VoiceOwnershipGrantedEvent({
    required String source,
    required String ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceOwnershipGranted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Ownership realtime concedido.',
         metadata: metadata,
       );
}

class VoiceOwnershipRejectedEvent extends VoiceRealtimeEvent {
  VoiceOwnershipRejectedEvent({
    required String source,
    required String requesterId,
    String? activeOwnerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceOwnershipRejected,
         source: source,
         ownerId: requesterId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Ownership realtime rejeitado.',
         severity: VoiceRealtimeEventSeverity.warning,
         metadata: {
           'requesterId': requesterId,
           'activeOwnerId': activeOwnerId,
           ...metadata,
         },
       );
}

class VoiceOwnershipRevokedEvent extends VoiceRealtimeEvent {
  VoiceOwnershipRevokedEvent({
    required String source,
    required String ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceOwnershipRevoked,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Ownership realtime revogado.',
         metadata: metadata,
       );
}

class VoiceRouteContextChangedEvent extends VoiceRealtimeEvent {
  VoiceRouteContextChangedEvent({
    required String source,
    String? routeId,
    String? routeName,
    String? previousRouteId,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceRouteContextChanged,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Contexto de rota realtime alterado.',
         metadata: {
           'routeId': routeId,
           'routeName': routeName,
           'previousRouteId': previousRouteId,
           ...metadata,
         },
       );
}

class VoiceRecoveryRetryingEvent extends VoiceRealtimeEvent {
  VoiceRecoveryRetryingEvent({
    required String source,
    required int attempt,
    required int delayMs,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceRecoveryRetrying,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Recovery aguardando backoff antes da tentativa.',
         metadata: {'attempt': attempt, 'delayMs': delayMs, ...metadata},
       );
}

class VoiceSessionRecoveredEvent extends VoiceRealtimeEvent {
  VoiceSessionRecoveredEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
  }) : super(
         type: VoiceRealtimeEventType.voiceSessionRecovered,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Sessao de voz recuperada.',
       );
}

class VoiceSystemDegradedEvent extends VoiceRealtimeEvent {
  VoiceSystemDegradedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceSystemDegraded,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Sistema de voz entrou em modo degradado.',
         severity: VoiceRealtimeEventSeverity.error,
         metadata: metadata,
       );
}

class VoiceStateChangedEvent extends VoiceRealtimeEvent {
  VoiceStateChangedEvent({
    required String source,
    required String previousState,
    required String nextState,
    String? ownerId,
    String? reason,
    String? message,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceStateChanged,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: message ?? '$previousState -> $nextState',
         metadata: {
           'previousState': previousState,
           'nextState': nextState,
           ...metadata,
         },
       );
}
