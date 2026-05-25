import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../contratos/audio_output_guard.dart';
import '../voice_command_handler.dart';

abstract class PlaybackService {
  String? get currentPath;

  Future<void> play();
  Future<void> stop();
  Future<void> pause();
}

class PlaybackCommandHandler implements VoiceCommandHandler<PlaybackIntent> {
  PlaybackCommandHandler({
    required PlaybackService service,
    required AudioOutputGuard audioOutputGuard,
    VoiceRealtimeEventBus? eventBus,
  }) : _service = service,
       _audioOutputGuard = audioOutputGuard,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final PlaybackService _service;
  final AudioOutputGuard _audioOutputGuard;
  final VoiceRealtimeEventBus _eventBus;

  @override
  Future<void> handle(PlaybackIntent intent, String correlationId) async {
    try {
      switch (intent.action) {
        case 'start':
          if (!_audioOutputGuard.isAudioOutputAvailable()) {
            _publishRejected(
              intent: intent,
              correlationId: correlationId,
              reason: 'audio_output_unavailable',
              metadata: {'action': intent.action},
            );
          }
          final path = _service.currentPath;
          if (path == null || path.isEmpty) {
            _publishRejected(
              intent: intent,
              correlationId: correlationId,
              reason: 'no_track_selected',
              metadata: {'action': intent.action},
            );
          }
          await _service.play();
        case 'stop':
          await _service.stop();
        case 'pause':
          await _service.pause();
        default:
          throw ArgumentError.value(intent.action, 'action');
      }
    } catch (error, stackTrace) {
      if (error is VoiceCommandHandlerException &&
          error.failureEventPublished) {
        rethrow;
      }
      _eventBus.publish(
        VoiceCommandFailedEvent(
          source: 'playback_command_handler',
          reason: 'playback_command_failed',
          correlationId: correlationId,
          intent: intent,
          metadata: {'action': intent.action, 'error': error.toString()},
        ),
      );
      throw VoiceCommandHandlerException(
        reason: 'playback_command_failed',
        cause: error,
        stackTrace: stackTrace,
        failureEventPublished: true,
      );
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

  Never _publishRejected({
    required PlaybackIntent intent,
    required String correlationId,
    required String reason,
    Map<String, Object?> metadata = const {},
  }) {
    _eventBus.publish(
      VoiceStateChangedEvent(
        source: 'playback_command_handler',
        previousState: 'commandPending',
        nextState: 'commandRejected',
        reason: reason,
        correlationId: correlationId,
        metadata: metadata,
      ),
    );
    _eventBus.publish(
      VoiceCommandFailedEvent(
        source: 'playback_command_handler',
        reason: reason,
        correlationId: correlationId,
        intent: intent,
        metadata: metadata,
      ),
    );
    throw VoiceCommandHandlerException(
      reason: reason,
      cause: StateError(reason),
      failureEventPublished: true,
    );
  }
}
