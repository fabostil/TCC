enum VoiceRealtimeEventType {
  audioOwnershipChanged,
  audioPipelineCaptureStarted,
  audioPipelineChunkReceived,
  audioPipelineCaptureStopped,
  audioPipelineError,
  audioPipelinePong,
  audioPipelineReady,
  audioPipelineShutdownComplete,
  eventChainCancelled,
  microphoneConflictDetected,
  playbackStarted,
  playbackStopped,
  recoverVoiceSessionRequested,
  recordingPaused,
  recordingResumed,
  recordingStarted,
  recordingStopped,
  recoveryAttempted,
  recoveryScheduled,
  recoverySkipped,
  silenceDetected,
  speechListeningFailed,
  speechResultReceived,
  speechListeningStarted,
  speechListeningStopped,
  startVoiceCaptureRequested,
  stopVoiceCaptureRequested,
  stopVoiceCaptureRejected,
  voiceOwnershipGranted,
  voiceOwnershipRejected,
  voiceOwnershipRequested,
  voiceOwnershipRevoked,
  voiceRouteContextChanged,
  voiceRecoveryRetrying,
  voiceCommandInterpreted,
  voiceSessionRecovered,
  voiceStateChanged,
  voiceSystemDegraded,
  voiceWakeWordDetected,
}

enum VoiceRealtimeEventSeverity { debug, info, warning, error }

class VoiceRealtimeEvent {
  VoiceRealtimeEvent({
    required this.type,
    required this.source,
    String? id,
    DateTime? timestamp,
    this.ownerId,
    String? correlationId,
    this.causationId,
    this.reason,
    this.message,
    this.severity = VoiceRealtimeEventSeverity.info,
    this.cancelable = false,
    this.metadata = const {},
  }) : id = id ?? VoiceRealtimeEventId.next(),
       timestamp = timestamp ?? DateTime.now(),
       correlationId = correlationId ?? id ?? VoiceRealtimeEventId.next();

  final String id;
  final VoiceRealtimeEventType type;
  final DateTime timestamp;
  final String source;
  final String? ownerId;
  final String correlationId;
  final String? causationId;
  final String? reason;
  final String? message;
  final VoiceRealtimeEventSeverity severity;
  final bool cancelable;
  final Map<String, Object?> metadata;

  bool get hasCorrelation => correlationId.isNotEmpty;

  @override
  String toString() {
    final owner = ownerId == null ? '' : ' owner=$ownerId';
    final cause = reason == null ? '' : ' reason=$reason';
    return '[voice-rt:${type.name}]$owner$cause ${message ?? ''}'.trim();
  }
}

class VoiceRealtimeEventId {
  VoiceRealtimeEventId._();

  static int _counter = 0;

  static String next() {
    _counter += 1;
    return 'vrt_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}
