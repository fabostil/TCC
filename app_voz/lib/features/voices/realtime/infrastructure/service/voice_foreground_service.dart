abstract class VoiceForegroundService {
  Future<void> startService({required String title, required String message});

  Future<void> updateMessage(String message);

  Future<void> stopService();
}
