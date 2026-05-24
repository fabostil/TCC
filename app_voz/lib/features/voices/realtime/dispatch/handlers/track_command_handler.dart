import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class TrackService {
  Future<void> record();
  Future<void> mute();
  Future<void> delete();
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
    switch (intent.action) {
      case 'record':
        await _service.record();
      case 'mute':
        await _service.mute();
      case 'delete':
        await _service.delete();
      default:
        throw ArgumentError.value(intent.action, 'action');
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
  @override
  Future<void> delete() async {}

  @override
  Future<void> mute() async {}

  @override
  Future<void> record() async {}
}
