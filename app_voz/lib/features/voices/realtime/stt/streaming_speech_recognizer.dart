import 'dart:typed_data';

abstract class StreamingSpeechRecognizer {
  Future<void> initializeRecognizer();
  Future<void> startRecognition(String correlationId);
  void feedAudioChunk(Uint8List chunk);
  Future<void> stopRecognition();
  Future<void> dispose();
}
