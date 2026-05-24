import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'text_to_speech_engine.dart';

class StubTextToSpeechEngine implements TextToSpeechEngine {
  StubTextToSpeechEngine({VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final VoiceRealtimeEventBus eventBus;

  String? lastText;
  String? lastCorrelationId;
  var speakCount = 0;
  var _disposed = false;
  var _speaking = false;

  @override
  Future<void> speak(String text, String correlationId) async {
    if (_disposed) {
      return;
    }

    if (_speaking) {
      await stop();
    }

    _speaking = true;
    speakCount += 1;
    lastText = text;
    lastCorrelationId = correlationId;
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'stub_text_to_speech_engine',
        previousState: 'ttsIdle',
        nextState: 'ttsSpeaking',
        reason: 'tts_stub_spoken',
        correlationId: correlationId,
        metadata: {'text': text},
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_speaking) {
      return;
    }
    _speaking = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    _disposed = true;
  }
}
