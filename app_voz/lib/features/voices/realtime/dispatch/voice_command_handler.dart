import '../nlu/voice_intent.dart';

abstract class VoiceCommandHandler<T extends VoiceIntent> {
  Future<void> handle(T intent, String correlationId);
}
