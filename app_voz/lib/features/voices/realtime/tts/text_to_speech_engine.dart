abstract class TextToSpeechEngine {
  Future<void> speak(String text, String correlationId);
  Future<void> stop();
  Future<void> dispose();
}
