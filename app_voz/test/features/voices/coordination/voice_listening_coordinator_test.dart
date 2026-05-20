import 'package:app_voz/features/voices/coordination/voice_listening_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VoiceListeningCoordinator coordinator;

  setUp(() {
    coordinator = VoiceListeningCoordinator.instance;
    coordinator.resetForTesting();
  });

  tearDown(() {
    coordinator.resetForTesting();
  });

  group('VoiceListeningCoordinator', () {
    test('reserva a escuta para um owner por vez', () {
      expect(coordinator.claimListening('home'), isTrue);
      expect(coordinator.activeOwnerId, 'home');

      expect(coordinator.canStartListening('home'), isTrue);
      expect(coordinator.claimListening('dashboard'), isFalse);
      expect(coordinator.activeOwnerId, 'home');

      coordinator.releaseOwner('dashboard');
      expect(coordinator.activeOwnerId, 'home');

      coordinator.releaseOwner('home');
      expect(coordinator.activeOwnerId, isNull);
      expect(coordinator.claimListening('dashboard'), isTrue);
    });

    test('modo gravacao bloqueia novas reservas e libera owner ativo', () {
      expect(coordinator.claimListening('editor'), isTrue);

      coordinator.enterRecordingMode();

      expect(coordinator.recordingModeActive, isTrue);
      expect(coordinator.activeOwnerId, isNull);
      expect(coordinator.canStartListening('editor'), isFalse);
      expect(coordinator.claimListening('editor'), isFalse);

      coordinator.exitRecordingMode();

      expect(coordinator.recordingModeActive, isFalse);
      expect(coordinator.claimListening('editor'), isTrue);
    });

    test('delays de reinicio seguem o motivo informado', () {
      expect(
        coordinator.restartDelayFor(VoiceRestartReason.normal),
        VoiceListeningCoordinator.restartDelayDefault,
      );
      expect(
        coordinator.restartDelayFor(VoiceRestartReason.afterError),
        VoiceListeningCoordinator.restartDelayAfterError,
      );
    });

    test(
      'reinicio agendado executa quando condicoes permanecem validas',
      () async {
        var reinicios = 0;

        coordinator.scheduleContinuousRestart(
          ownerId: 'home',
          shouldRestart: () => true,
          onRestart: () async {
            reinicios++;
          },
        );

        await Future<void>.delayed(
          VoiceListeningCoordinator.restartDelayDefault +
              const Duration(milliseconds: 100),
        );

        expect(reinicios, 1);
      },
    );

    test('reinicio agendado e invalidado quando a rota muda', () async {
      var reinicios = 0;

      coordinator.scheduleContinuousRestart(
        ownerId: 'home',
        shouldRestart: () => true,
        onRestart: () async {
          reinicios++;
        },
      );

      coordinator.onRouteDidPop();

      await Future<void>.delayed(
        VoiceListeningCoordinator.restartDelayDefault +
            const Duration(milliseconds: 100),
      );

      expect(reinicios, 0);
    });

    test('reinicio agendado respeita shouldRestart falso', () async {
      var reinicios = 0;

      coordinator.scheduleContinuousRestart(
        ownerId: 'home',
        shouldRestart: () => false,
        onRestart: () async {
          reinicios++;
        },
      );

      await Future<void>.delayed(
        VoiceListeningCoordinator.restartDelayDefault +
            const Duration(milliseconds: 100),
      );

      expect(reinicios, 0);
    });
  });
}
