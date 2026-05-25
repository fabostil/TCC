import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class TrackService {
  Future<void> startRecordingTrack();
  Future<void> muteSelectedTrack();
  Future<void> deleteSelectedTrack();
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
          await _service.startRecordingTrack();
        case 'mute':
          await _service.muteSelectedTrack();
        case 'delete':
          await _service.deleteSelectedTrack();
        default:
          throw ArgumentError.value(intent.action, 'action');
      }
    } catch (error, stackTrace) {
      _eventBus.publish(
        VoiceCommandFailedEvent(
          source: 'track_command_handler',
          reason: 'track_command_failed',
          correlationId: correlationId,
          intent: intent,
          metadata: {'action': intent.action, 'error': error.toString()},
        ),
      );
      throw VoiceCommandHandlerException(
        reason: 'track_command_failed',
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
  Future<void> deleteSelectedTrack() async {}

  @override
  Future<void> muteSelectedTrack() async {}

  @override
  Future<void> startRecordingTrack() async {}
}
