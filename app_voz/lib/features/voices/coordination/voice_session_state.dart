enum VoiceSessionPhase {
  idle,
  listening,
  processingCommand,
  aiThinking,
  manualPaused,
  recordingLocked,
  error,
}

extension VoiceSessionPhaseLabel on VoiceSessionPhase {
  String get diagnosticName {
    return switch (this) {
      VoiceSessionPhase.idle => 'idle',
      VoiceSessionPhase.listening => 'listening',
      VoiceSessionPhase.processingCommand => 'processing',
      VoiceSessionPhase.aiThinking => 'processing',
      VoiceSessionPhase.manualPaused => 'paused',
      VoiceSessionPhase.recordingLocked => 'recording',
      VoiceSessionPhase.error => 'error',
    };
  }
}

class VoiceSessionState {
  const VoiceSessionState({required this.phase, this.message, this.updatedAt});

  const VoiceSessionState.idle()
    : phase = VoiceSessionPhase.idle,
      message = null,
      updatedAt = null;

  final VoiceSessionPhase phase;
  final String? message;
  final DateTime? updatedAt;

  bool get isListening => phase == VoiceSessionPhase.listening;

  bool get isThinking => phase == VoiceSessionPhase.aiThinking;

  bool get isBusy =>
      phase == VoiceSessionPhase.processingCommand ||
      phase == VoiceSessionPhase.aiThinking;

  bool get canStartListening =>
      phase == VoiceSessionPhase.idle ||
      phase == VoiceSessionPhase.error ||
      phase == VoiceSessionPhase.manualPaused;

  VoiceSessionState copyWith({
    VoiceSessionPhase? phase,
    String? message,
    bool clearMessage = false,
    DateTime? updatedAt,
  }) {
    return VoiceSessionState(
      phase: phase ?? this.phase,
      message: clearMessage ? null : message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  VoiceSessionState transitionTo(
    VoiceSessionPhase nextPhase, {
    String? message,
    DateTime? now,
  }) {
    return VoiceSessionState(
      phase: nextPhase,
      message: message,
      updatedAt: now ?? DateTime.now(),
    );
  }
}
