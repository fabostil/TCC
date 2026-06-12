import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class TrackService {
  Future<void> startRecordingTrack({
    TrackIntent? intent,
    String? correlationId,
  });
  Future<void> muteSelectedTrack({TrackIntent? intent, String? correlationId});
  Future<void> deleteSelectedTrack({
    TrackIntent? intent,
    String? correlationId,
  });
}

class TrackCommandFailure implements Exception {
  TrackCommandFailure({
    required this.reason,
    this.metadata = const {},
    this.failureEventPublished = false,
  });

  final String reason;
  final Map<String, Object?> metadata;
  final bool failureEventPublished;

  @override
  String toString() => 'TrackCommandFailure($reason)';
}

class TrackCommandHandler implements VoiceCommandHandler<TrackIntent> {
  TrackCommandHandler({
    required TrackService service,
    VoiceRealtimeEventBus? eventBus,
  }) : _service = service,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final TrackService _service;
  final VoiceRealtimeEventBus _eventBus;

  @override
  Future<void> handle(TrackIntent intent, String correlationId) async {
    try {
      switch (intent.action) {
        case 'record':
          await _service.startRecordingTrack(
            intent: intent,
            correlationId: correlationId,
          );
        case 'mute':
          await _service.muteSelectedTrack(
            intent: intent,
            correlationId: correlationId,
          );
        case 'delete':
          await _service.deleteSelectedTrack(
            intent: intent,
            correlationId: correlationId,
          );
        default:
          throw ArgumentError.value(intent.action, 'action');
      }
    } catch (error, stackTrace) {
      final failure = error is TrackCommandFailure ? error : null;
      final reason = failure?.reason ?? 'track_command_failed';
      if (failure == null || !failure.failureEventPublished) {
        _eventBus.publish(
          VoiceCommandFailedEvent(
            source: 'track_command_handler',
            reason: reason,
            correlationId: correlationId,
            intent: intent,
            metadata: {
              'action': intent.action,
              'error': error.toString(),
              ...?failure?.metadata,
            },
          ),
        );
      }
      throw VoiceCommandHandlerException(
        reason: reason,
        cause: error,
        stackTrace: stackTrace,
        failureEventPublished: true,
      );
    }

    _eventBus.publish(
      VoiceStateChangedEvent(
        source: 'track_command_handler',
        previousState: 'commandPending',
        nextState: 'commandHandled',
        reason: 'track_command_dispatched',
        correlationId: correlationId,
        metadata: {'action': intent.action},
      ),
    );
  }
}

class StubTrackService implements TrackService {
  // Adapter seguro ate existir dominio real de tracks/multipista com mute.
  @override
  Future<void> deleteSelectedTrack({
    TrackIntent? intent,
    String? correlationId,
  }) async {}

  @override
  Future<void> muteSelectedTrack({
    TrackIntent? intent,
    String? correlationId,
  }) async {}

  @override
  Future<void> startRecordingTrack({
    TrackIntent? intent,
    String? correlationId,
  }) async {}
}
