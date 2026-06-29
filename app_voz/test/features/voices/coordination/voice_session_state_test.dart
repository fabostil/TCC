import 'package:app_voz/features/voices/coordination/voice_session_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceSessionState', () {
    test('expoe flags derivadas da fase atual', () {
      const idle = VoiceSessionState.idle();
      expect(idle.isListening, isFalse);
      expect(idle.isThinking, isFalse);
      expect(idle.isBusy, isFalse);
      expect(idle.canStartListening, isTrue);

      const listening = VoiceSessionState(phase: VoiceSessionPhase.listening);
      expect(listening.isListening, isTrue);
      expect(listening.canStartListening, isFalse);

      const thinking = VoiceSessionState(phase: VoiceSessionPhase.aiThinking);
      expect(thinking.isThinking, isTrue);
      expect(thinking.isBusy, isTrue);
    });

    test('transicao registra fase, mensagem e timestamp', () {
      final now = DateTime(2026, 5, 19, 20, 30);

      final next = const VoiceSessionState.idle().transitionTo(
        VoiceSessionPhase.error,
        message: 'Nao entendi.',
        now: now,
      );

      expect(next.phase, VoiceSessionPhase.error);
      expect(next.message, 'Nao entendi.');
      expect(next.updatedAt, now);
      expect(next.canStartListening, isTrue);
    });

    test('copyWith preserva mensagem ou limpa explicitamente', () {
      const state = VoiceSessionState(
        phase: VoiceSessionPhase.listening,
        message: 'Ouvindo...',
      );

      expect(
        state.copyWith(phase: VoiceSessionPhase.processingCommand).message,
        'Ouvindo...',
      );
      expect(state.copyWith(clearMessage: true).message, isNull);
    });
  });
}
