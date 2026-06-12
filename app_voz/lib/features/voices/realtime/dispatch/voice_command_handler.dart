import '../nlu/voice_intent.dart';

abstract class VoiceCommandHandler<T extends VoiceIntent> {
  Future<void> handle(T intent, String correlationId);
}

abstract class ConfirmableVoiceCommandHandler<T extends VoiceIntent>
    implements VoiceCommandHandler<T> {
  Future<void> handleConfirmation(
    T intent,
    bool approved,
    String correlationId,
  );
}

class VoiceCommandHandlerException implements Exception {
  const VoiceCommandHandlerException({
    required this.reason,
    required this.cause,
    this.stackTrace,
    this.failureEventPublished = false,
  });

  final String reason;
  final Object cause;
  final StackTrace? stackTrace;
  final bool failureEventPublished;

  @override
  String toString() => 'VoiceCommandHandlerException($reason): $cause';
}
