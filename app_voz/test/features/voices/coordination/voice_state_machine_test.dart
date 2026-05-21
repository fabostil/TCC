import 'package:app_voz/features/voices/coordination/voice_diagnostics.dart';
import 'package:app_voz/features/voices/coordination/voice_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceStateMachine', () {
    test('inicia em idle e expoe flags de sessao realtime', () {
      final machine = VoiceStateMachine();

      expect(machine.state, VoiceState.idle);
      expect(machine.snapshot.canStartListening, isTrue);
      expect(machine.snapshot.microphoneReserved, isFalse);
    });

    test('registra transicoes de estado com motivo e owner', () {
      final diagnostics = VoiceDiagnostics();
      final machine = VoiceStateMachine(diagnostics: diagnostics);
      final now = DateTime(2026, 5, 20, 12);

      final snapshot = machine.transitionTo(
        VoiceState.listening,
        ownerId: 'home',
        message: 'Ouvindo.',
        reason: 'auto_start',
        now: now,
      );

      expect(snapshot.state, VoiceState.listening);
      expect(snapshot.previousState, VoiceState.idle);
      expect(snapshot.ownerId, 'home');
      expect(snapshot.updatedAt, now);
      expect(snapshot.microphoneReserved, isTrue);
      expect(diagnostics.latest?.type, VoiceDiagnosticEventType.stateTransition);
      expect(diagnostics.latest?.reason, 'auto_start');
    });

    test('bloqueia transicao invalida saindo de disabled sem force', () {
      final diagnostics = VoiceDiagnostics();
      final machine = VoiceStateMachine(diagnostics: diagnostics);

      machine.transitionTo(VoiceState.disabled, reason: 'settings');
      final snapshot = machine.transitionTo(
        VoiceState.listening,
        ownerId: 'home',
        reason: 'invalid',
      );

      expect(snapshot.state, VoiceState.disabled);
      expect(
        diagnostics.latest?.type,
        VoiceDiagnosticEventType.error,
      );
    });
  });
}
