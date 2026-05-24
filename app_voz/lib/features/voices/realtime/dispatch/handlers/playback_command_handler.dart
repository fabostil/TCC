import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class PlaybackService {
  Future<void> start();
  Future<void> stop();
  Future<void> pause();
}

class PlaybackCommandHandler implements VoiceCommandHandler<PlaybackIntent> {
  PlaybackCommandHandler({
    required PlaybackService service,
    VoiceRealtimeEventBus? eventBus,
  }) : _service = service,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final PlaybackService _service;
  final VoiceRealtimeEventBus _eventBus;

  @override
  Future<void> handle(PlaybackIntent intent, String correlationId) async {
    switch (intent.action) {
      case 'start':
        await _service.start();
      case 'stop':
        await _service.stop();
      case 'pause':
        await _service.pause();
      default:
        throw ArgumentError.value(intent.action, 'action');
    }

    _eventBus.publish(
      VoiceStateChangedEvent(
        source: 'playback_command_handler',
        previousState: 'commandPending',
        nextState: 'commandHandled',
        reason: 'playback_command_dispatched',
        correlationId: correlationId,
        metadata: {'action': intent.action},
      ),
    );
  }
}

class StubPlaybackService implements PlaybackService {
  @override
  Future<void> pause() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
