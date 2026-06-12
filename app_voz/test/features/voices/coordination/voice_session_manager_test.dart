import 'package:app_voz/features/voices/coordination/voice_diagnostics.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/coordination/voice_state_machine.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VoiceSessionManager manager;

  setUp(() {
    manager = VoiceSessionManager.instance;
    manager.resetForTesting();
  });

  tearDown(() {
    manager.resetForTesting();
  });

  group('VoiceSessionManager', () {
    test('garante ownership exclusivo da escuta STT', () {
      expect(manager.claimListening('home'), isTrue);
      expect(manager.activeOwnerId, 'home');
      expect(manager.audioOwnerType, VoiceAudioOwnerType.stt);
      expect(manager.stateMachine.state, VoiceState.listening);

      expect(manager.claimListening('dashboard'), isFalse);
      expect(manager.activeOwnerId, 'home');
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );

      manager.releaseOwner('home');
      expect(manager.activeOwnerId, isNull);
      expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
    });

    test('modo gravacao bloqueia STT e registra conflito de microfone', () {
      manager.enterRecordingMode(ownerId: 'editor');

      expect(manager.recordingActive, isTrue);
      expect(manager.stateMachine.state, VoiceState.recording);
      expect(manager.claimListening('home'), isFalse);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );

      manager.exitRecordingMode(ownerId: 'editor');
      expect(manager.recordingActive, isFalse);
      expect(manager.claimListening('home'), isTrue);
    });

    test('playback e bloqueado durante gravacao', () async {
      manager.enterRecordingMode(ownerId: 'editor');

      final started = await manager.beginPlayback(ownerId: 'player');

      expect(started, isFalse);
      expect(manager.recordingActive, isTrue);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );
    });

    test(
      'publica eventos realtime para listening, recording e playback',
      () async {
        final bus = manager.diagnostics.eventBus;

        expect(manager.claimListening('home'), isTrue);
        manager.releaseOwner('home');
        manager.enterRecordingMode(ownerId: 'editor');
        manager.exitRecordingMode(ownerId: 'editor');
        final playbackStarted = await manager.beginPlayback(ownerId: 'player');
        manager.endPlayback(ownerId: 'player');

        expect(playbackStarted, isTrue);
        expect(
          bus.timeline.map((event) => event.type),
          containsAll([
            VoiceRealtimeEventType.recordingStarted,
            VoiceRealtimeEventType.recordingStopped,
            VoiceRealtimeEventType.playbackStarted,
            VoiceRealtimeEventType.playbackStopped,
            VoiceRealtimeEventType.voiceStateChanged,
          ]),
        );
      },
    );

    test(
      'cancelamento por owner antigo nao derruba sessao ativa nova',
      () async {
        expect(manager.claimListening('home'), isTrue);

        await manager.cancelListening(ownerId: 'dashboard');

        expect(manager.activeOwnerId, 'home');
        expect(manager.audioOwnerType, VoiceAudioOwnerType.stt);
        expect(manager.stateMachine.state, VoiceState.listening);
      },
    );

    test('recovery respeita limite de tentativas e evita loop infinito', () {
      for (var i = 0; i < VoiceSessionManager.maxRecoveryAttempts; i++) {
        manager.stateMachine.incrementRecoveryAttempts();
      }

      var recovered = false;
      manager.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {
          recovered = true;
        },
      );

      expect(recovered, isFalse);
      expect(manager.stateMachine.state, VoiceState.error);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.stateTransition,
      );
      expect(
        manager.diagnostics.events.any(
          (event) => event.type == VoiceDiagnosticEventType.recoverySkipped,
        ),
        isTrue,
      );
    });
  });
}
