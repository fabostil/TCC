import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class MetronomeService {
  Future<void> setBpm(int bpm);
}

class MetronomeCommandHandler implements VoiceCommandHandler<MetronomeIntent> {
  MetronomeCommandHandler({
    required MetronomeService service,
    VoiceRealtimeEventBus? eventBus,
  }) : _service = service,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final MetronomeService _service;
  final VoiceRealtimeEventBus _eventBus;

  @override
  Future<void> handle(MetronomeIntent intent, String correlationId) async {
    await _service.setBpm(intent.bpm);
    _eventBus.publish(
      VoiceStateChangedEvent(
        source: 'metronome_command_handler',
        previousState: 'commandPending',
        nextState: 'commandHandled',
        reason: 'metronome_bpm_set',
        correlationId: correlationId,
        metadata: {'bpm': intent.bpm},
      ),
    );
  }
}

class StubMetronomeService implements MetronomeService {
  @override
  Future<void> setBpm(int bpm) async {}
}
