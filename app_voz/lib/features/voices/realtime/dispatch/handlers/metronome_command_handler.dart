import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

abstract class MetronomeService {
  Future<void> updateBpm(int bpm);
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
    try {
      await _service.updateBpm(intent.bpm);
    } catch (error, stackTrace) {
      _eventBus.publish(
        VoiceCommandFailedEvent(
          source: 'metronome_command_handler',
          reason: 'metronome_update_failed',
          correlationId: correlationId,
          intent: intent,
          metadata: {'error': error.toString()},
        ),
      );
      throw VoiceCommandHandlerException(
        reason: 'metronome_update_failed',
        cause: error,
        stackTrace: stackTrace,
        failureEventPublished: true,
      );
    }

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
  // Adapter seguro ate existir um controlador real de metronomo no dominio.
  @override
  Future<void> updateBpm(int bpm) async {}
}
