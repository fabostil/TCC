import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import 'voice_foreground_service.dart';

class StubVoiceForegroundService implements VoiceForegroundService {
  StubVoiceForegroundService({VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final VoiceRealtimeEventBus eventBus;

  var started = false;
  String? title;
  String? message;

  @override
  Future<void> startService({
    required String title,
    required String message,
  }) async {
    started = true;
    this.title = title;
    this.message = message;
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'stub_voice_foreground_service',
        previousState: 'foregroundStopped',
        nextState: 'foregroundStarted',
        reason: 'foreground_service_started',
        correlationId: 'foreground_service',
        metadata: {'title': title, 'message': message},
      ),
    );
  }

  @override
  Future<void> updateMessage(String message) async {
    this.message = message;
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'stub_voice_foreground_service',
        previousState: 'foregroundStarted',
        nextState: 'foregroundStarted',
        reason: 'foreground_service_updated',
        correlationId: 'foreground_service',
        metadata: {'message': message},
      ),
    );
  }

  @override
  Future<void> stopService() async {
    if (!started) {
      return;
    }
    started = false;
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'stub_voice_foreground_service',
        previousState: 'foregroundStarted',
        nextState: 'foregroundStopped',
        reason: 'foreground_service_stopped',
        correlationId: 'foreground_service',
      ),
    );
  }
}
