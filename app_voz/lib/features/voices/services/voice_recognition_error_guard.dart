class VoiceRecognitionErrorDecision {
  const VoiceRecognitionErrorDecision({
    required this.shouldPresent,
    required this.shouldRecover,
  });

  final bool shouldPresent;
  final bool shouldRecover;
}

class VoiceRecognitionErrorGuard {
  VoiceRecognitionErrorGuard({
    this.cooldown = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const friendlyMessage =
      'Não consegui ouvir o comando agora. Tente novamente em alguns segundos.';

  final Duration cooldown;
  final DateTime Function() _now;

  DateTime? _lastPresentedAt;

  VoiceRecognitionErrorDecision evaluate(String _) {
    final now = _now();
    final repeatedWithinCooldown =
        _lastPresentedAt != null &&
        now.difference(_lastPresentedAt!) < cooldown;

    if (repeatedWithinCooldown) {
      return const VoiceRecognitionErrorDecision(
        shouldPresent: false,
        shouldRecover: false,
      );
    }

    _lastPresentedAt = now;
    return const VoiceRecognitionErrorDecision(
      shouldPresent: true,
      shouldRecover: true,
    );
  }

  void reset() {
    _lastPresentedAt = null;
  }
}
