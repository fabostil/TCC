import 'dart:typed_data';

import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'streaming_speech_recognizer.dart';

/// Placeholder arquitetural para o futuro STT streaming.
///
/// Esta classe nao abre microfone, nao chama SpeechService e nao tenta fazer
/// reconhecimento real. Ela existe para manter o RuntimeEngine desacoplado do
/// motor de STT enquanto a engine de streaming ainda nao foi escolhida.
class UnsupportedSpeechRecognizer implements StreamingSpeechRecognizer {
  UnsupportedSpeechRecognizer({VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final VoiceRealtimeEventBus eventBus;

  bool _initialized = false;
  bool _recognizing = false;
  String? _correlationId;
  int _chunksReceived = 0;
  int _bytesReceived = 0;

  @override
  Future<void> initializeRecognizer() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'unsupported_speech_recognizer',
        reason: 'streaming_stt_unavailable',
        metadata: {'stage': 'initialize'},
      ),
    );
  }

  @override
  Future<void> startRecognition(String correlationId) async {
    await initializeRecognizer();
    _recognizing = true;
    _correlationId = correlationId;
    _chunksReceived = 0;
    _bytesReceived = 0;
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'unsupported_speech_recognizer',
        reason: 'streaming_stt_placeholder_active',
        correlationId: correlationId,
        metadata: {'stage': 'startRecognition'},
      ),
    );
  }

  @override
  void feedAudioChunk(Uint8List chunk) {
    if (!_recognizing) {
      return;
    }
    _chunksReceived += 1;
    _bytesReceived += chunk.length;
  }

  @override
  Future<void> stopRecognition() async {
    if (!_recognizing) {
      return;
    }
    final correlationId = _correlationId;
    _recognizing = false;
    _correlationId = null;
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'unsupported_speech_recognizer',
        reason: 'streaming_stt_placeholder_stopped',
        correlationId: correlationId,
        metadata: {
          'stage': 'stopRecognition',
          'chunksReceived': _chunksReceived,
          'bytesReceived': _bytesReceived,
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await stopRecognition();
    _initialized = false;
  }
}
