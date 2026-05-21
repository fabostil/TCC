import 'dart:async';

import 'package:flutter/foundation.dart';

import '../realtime/voice_realtime_event.dart';
import '../realtime/voice_realtime_event_bus.dart';

enum VoiceDiagnosticEventType {
  stateTransition,
  microphoneConflict,
  listeningStarted,
  listeningStopped,
  recordingStarted,
  recordingStopped,
  playbackStarted,
  playbackStopped,
  recoveryScheduled,
  recoveryAttempted,
  recoverySkipped,
  error,
}

class VoiceDiagnosticEvent {
  const VoiceDiagnosticEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.ownerId,
    this.reason,
    this.metadata = const {},
    this.realtimeEventId,
    this.correlationId,
  });

  final VoiceDiagnosticEventType type;
  final DateTime timestamp;
  final String message;
  final String? ownerId;
  final String? reason;
  final Map<String, Object?> metadata;
  final String? realtimeEventId;
  final String? correlationId;

  @override
  String toString() {
    final owner = ownerId == null ? '' : ' owner=$ownerId';
    final cause = reason == null ? '' : ' reason=$reason';
    return '[voice:${type.name}]$owner$cause $message';
  }
}

class VoiceDiagnostics extends ChangeNotifier {
  VoiceDiagnostics({this.maxEvents = 200, VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance {
    _eventSubscription = this.eventBus.stream.listen(_recordRealtimeEvent);
  }

  final int maxEvents;
  final VoiceRealtimeEventBus eventBus;
  final List<VoiceDiagnosticEvent> _events = [];
  StreamSubscription<VoiceRealtimeEvent>? _eventSubscription;

  List<VoiceDiagnosticEvent> get events => List.unmodifiable(_events);

  VoiceDiagnosticEvent? get latest => _events.isEmpty ? null : _events.last;

  void record(
    VoiceDiagnosticEventType type, {
    required String message,
    String? ownerId,
    String? reason,
    Map<String, Object?> metadata = const {},
    DateTime? now,
    String? realtimeEventId,
    String? correlationId,
  }) {
    final event = VoiceDiagnosticEvent(
      type: type,
      timestamp: now ?? DateTime.now(),
      message: message,
      ownerId: ownerId,
      reason: reason,
      metadata: metadata,
      realtimeEventId: realtimeEventId,
      correlationId: correlationId,
    );

    _append(event);
  }

  void _recordRealtimeEvent(VoiceRealtimeEvent event) {
    _append(
      VoiceDiagnosticEvent(
        type: event.type.toDiagnosticType(),
        timestamp: event.timestamp,
        message: event.message ?? event.type.name,
        ownerId: event.ownerId,
        reason: event.reason,
        metadata: {
          'source': event.source,
          'severity': event.severity.name,
          ...event.metadata,
        },
        realtimeEventId: event.id,
        correlationId: event.correlationId,
      ),
    );
  }

  void _append(VoiceDiagnosticEvent event) {
    _events.add(event);
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }

    debugPrint(event.toString());
    notifyListeners();
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }
}

extension VoiceRealtimeDiagnosticMapping on VoiceRealtimeEventType {
  VoiceDiagnosticEventType toDiagnosticType() {
    return switch (this) {
      VoiceRealtimeEventType.audioOwnershipChanged =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.audioPipelineCaptureStarted =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.audioPipelineCaptureStopped =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.audioPipelineError =>
        VoiceDiagnosticEventType.error,
      VoiceRealtimeEventType.audioPipelinePong =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.audioPipelineReady =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.audioPipelineShutdownComplete =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.eventChainCancelled =>
        VoiceDiagnosticEventType.recoverySkipped,
      VoiceRealtimeEventType.microphoneConflictDetected =>
        VoiceDiagnosticEventType.microphoneConflict,
      VoiceRealtimeEventType.playbackStarted =>
        VoiceDiagnosticEventType.playbackStarted,
      VoiceRealtimeEventType.playbackStopped =>
        VoiceDiagnosticEventType.playbackStopped,
      VoiceRealtimeEventType.recoverVoiceSessionRequested =>
        VoiceDiagnosticEventType.recoveryScheduled,
      VoiceRealtimeEventType.recordingPaused =>
        VoiceDiagnosticEventType.recordingStopped,
      VoiceRealtimeEventType.recordingResumed =>
        VoiceDiagnosticEventType.recordingStarted,
      VoiceRealtimeEventType.recordingStarted =>
        VoiceDiagnosticEventType.recordingStarted,
      VoiceRealtimeEventType.recordingStopped =>
        VoiceDiagnosticEventType.recordingStopped,
      VoiceRealtimeEventType.recoveryAttempted =>
        VoiceDiagnosticEventType.recoveryAttempted,
      VoiceRealtimeEventType.recoveryScheduled =>
        VoiceDiagnosticEventType.recoveryScheduled,
      VoiceRealtimeEventType.recoverySkipped =>
        VoiceDiagnosticEventType.recoverySkipped,
      VoiceRealtimeEventType.silenceDetected =>
        VoiceDiagnosticEventType.recordingStopped,
      VoiceRealtimeEventType.speechListeningFailed =>
        VoiceDiagnosticEventType.error,
      VoiceRealtimeEventType.speechResultReceived =>
        VoiceDiagnosticEventType.listeningStarted,
      VoiceRealtimeEventType.speechListeningStarted =>
        VoiceDiagnosticEventType.listeningStarted,
      VoiceRealtimeEventType.speechListeningStopped =>
        VoiceDiagnosticEventType.listeningStopped,
      VoiceRealtimeEventType.stopVoiceCaptureRequested =>
        VoiceDiagnosticEventType.listeningStopped,
      VoiceRealtimeEventType.stopVoiceCaptureRejected =>
        VoiceDiagnosticEventType.recoverySkipped,
      VoiceRealtimeEventType.voiceOwnershipGranted =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.voiceOwnershipRejected =>
        VoiceDiagnosticEventType.microphoneConflict,
      VoiceRealtimeEventType.voiceOwnershipRequested =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.voiceOwnershipRevoked =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.voiceRouteContextChanged =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.voiceRecoveryRetrying =>
        VoiceDiagnosticEventType.recoveryScheduled,
      VoiceRealtimeEventType.voiceSessionRecovered =>
        VoiceDiagnosticEventType.recoveryAttempted,
      VoiceRealtimeEventType.voiceStateChanged =>
        VoiceDiagnosticEventType.stateTransition,
      VoiceRealtimeEventType.voiceSystemDegraded =>
        VoiceDiagnosticEventType.error,
    };
  }
}
