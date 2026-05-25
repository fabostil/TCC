// ignore_for_file: use_super_parameters

import 'dart:typed_data';

import 'nlu/voice_intent.dart';
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

class AudioPipelineChunkReceivedEvent extends VoiceRealtimeEvent {
  AudioPipelineChunkReceivedEvent({
    required String source,
    required this.chunk,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.audioPipelineChunkReceived,
         source: source,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Chunk de audio realtime recebido.',
         metadata: {'bytes': chunk.length, ...metadata},
       );

  final Uint8List chunk;
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
    this.isIsolateEngine = false,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.silenceDetected,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Silencio detectado.',
         metadata: {
           'silenceMs': silenceMs,
           'level': level,
           'isIsolateEngine': isIsolateEngine,
           ...metadata,
         },
       );

  final bool isIsolateEngine;
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
    required this.text,
    this.isFinal = false,
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
         metadata: {'text': text, 'isFinal': isFinal},
       );

  final bool isFinal;
  final String text;
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

class StartVoiceCaptureRequestedEvent extends VoiceRealtimeEvent {
  StartVoiceCaptureRequestedEvent({
    required String source,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.startVoiceCaptureRequested,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Inicio seguro de captura de voz solicitado.',
         cancelable: true,
         metadata: metadata,
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

class VoiceCommandInterpretedEvent extends VoiceRealtimeEvent {
  VoiceCommandInterpretedEvent({
    required String source,
    required this.intent,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceCommandInterpreted,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Comando de voz interpretado.',
         metadata: {
           'intentType': intent.runtimeType.toString(),
           'rawText': intent.rawText,
           ..._intentMetadata(intent),
           ...metadata,
         },
       );

  final VoiceIntent intent;
}

class VoiceCommandFailedEvent extends VoiceRealtimeEvent {
  VoiceCommandFailedEvent({
    required String source,
    required String reason,
    this.intent,
    String? ownerId,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceCommandFailed,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Falha ao executar comando de voz.',
         severity: VoiceRealtimeEventSeverity.error,
         metadata: {
           if (intent != null) 'intentType': intent.runtimeType.toString(),
           if (intent != null) 'rawText': intent.rawText,
           if (intent != null) ..._intentMetadata(intent),
           ...metadata,
         },
       );

  final VoiceIntent? intent;
}

class VoiceCommandConfirmationRequiredEvent extends VoiceRealtimeEvent {
  VoiceCommandConfirmationRequiredEvent({
    required String source,
    required this.action,
    required this.intent,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceCommandConfirmationRequired,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Confirmacao de comando de voz solicitada.',
         cancelable: true,
         metadata: {
           'action': action,
           'intentType': intent.runtimeType.toString(),
           'rawText': intent.rawText,
           ..._intentMetadata(intent),
           ...metadata,
         },
       );

  final String action;
  final VoiceIntent intent;
}

class VoiceCommandConfirmationResolvedEvent extends VoiceRealtimeEvent {
  VoiceCommandConfirmationResolvedEvent({
    required String source,
    required this.action,
    required this.intent,
    required this.approved,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceCommandConfirmationResolved,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: approved
             ? 'Comando de voz confirmado.'
             : 'Comando de voz cancelado.',
         metadata: {
           'action': action,
           'approved': approved,
           'intentType': intent.runtimeType.toString(),
           'rawText': intent.rawText,
           ..._intentMetadata(intent),
           ...metadata,
         },
       );

  final String action;
  final VoiceIntent intent;
  final bool approved;
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

Map<String, Object?> _intentMetadata(VoiceIntent intent) {
  return switch (intent) {
    MetronomeIntent(:final bpm) => {'bpm': bpm},
    PlaybackIntent(:final action) => {'action': action},
    TrackIntent(:final action) => {'action': action},
    DeleteLastRecordingIntent() => {'recordingAction': 'deleteLast'},
    RenameLastRecordingIntent(:final newName) => {
      'recordingAction': 'renameLast',
      'newName': newName,
    },
    ConfirmIntent() => {'flowAction': 'confirm'},
    CancelIntent() => {'flowAction': 'cancel'},
    UnknownIntent() => const {},
  };
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

class VoiceWakeWordDetectedEvent extends VoiceRealtimeEvent {
  VoiceWakeWordDetectedEvent({
    required String source,
    required this.detectedAt,
    String? ownerId,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) : super(
         type: VoiceRealtimeEventType.voiceWakeWordDetected,
         source: source,
         ownerId: ownerId,
         reason: reason,
         correlationId: correlationId,
         causationId: causationId,
         message: 'Palavra de ativacao detectada.',
         metadata: {'detectedAt': detectedAt.toIso8601String(), ...metadata},
       );

  final DateTime detectedAt;
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
