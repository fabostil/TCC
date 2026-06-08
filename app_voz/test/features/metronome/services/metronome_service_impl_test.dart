import 'package:app_voz/features/metronome/services/metronome_service_impl.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contratos/audio_output_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MetronomeServiceImpl', () {
    testWidgets('usa Timer.periodic pelo intervalo calculado a partir do BPM', (
      tester,
    ) async {
      var ticks = 0;
      final service = MetronomeServiceImpl(
        audioOutputGuard: _FakeAudioOutputGuard(),
        tickPlayer: () async {
          ticks += 1;
        },
      );

      await service.start(60000);
      await tester.pump(const Duration(milliseconds: 3));

      expect(ticks, 3);
      expect(service.activeBpm, 60000);
      expect(service.isRunning, isTrue);

      await service.dispose();
    });

    testWidgets('start e idempotente quando o BPM ativo nao muda', (
      tester,
    ) async {
      var ticks = 0;
      final service = MetronomeServiceImpl(
        audioOutputGuard: _FakeAudioOutputGuard(),
        tickPlayer: () async {
          ticks += 1;
        },
      );

      await service.start(60000);
      await service.start(60000);
      await tester.pump(const Duration(milliseconds: 2));

      expect(ticks, 2);

      await service.dispose();
    });

    testWidgets('troca de BPM cancela timer anterior antes de criar outro', (
      tester,
    ) async {
      var ticks = 0;
      final service = MetronomeServiceImpl(
        audioOutputGuard: _FakeAudioOutputGuard(),
        tickPlayer: () async {
          ticks += 1;
        },
      );

      await service.start(60000);
      await tester.pump(const Duration(milliseconds: 1));
      await service.start(30000);
      await tester.pump(const Duration(milliseconds: 3));

      expect(ticks, 2);
      expect(service.activeBpm, 30000);

      await service.dispose();
    });

    testWidgets('nao toca tick quando canal de saida esta indisponivel', (
      tester,
    ) async {
      var ticks = 0;
      final guard = _FakeAudioOutputGuard()..available = false;
      final service = MetronomeServiceImpl(
        audioOutputGuard: guard,
        tickPlayer: () async {
          ticks += 1;
        },
      );

      await service.start(60000);
      await tester.pump(const Duration(milliseconds: 3));

      expect(ticks, 0);

      await service.dispose();
    });

    testWidgets('stop e dispose cancelam timer ativo imediatamente', (
      tester,
    ) async {
      var ticks = 0;
      final service = MetronomeServiceImpl(
        audioOutputGuard: _FakeAudioOutputGuard(),
        tickPlayer: () async {
          ticks += 1;
        },
      );

      await service.start(60000);
      await service.stop();
      await tester.pump(const Duration(milliseconds: 3));
      expect(ticks, 0);

      await service.start(60000);
      await service.dispose();
      await tester.pump(const Duration(milliseconds: 3));
      expect(ticks, 0);
    });
  });
}

class _FakeAudioOutputGuard implements AudioOutputGuard {
  var available = true;

  @override
  bool isAudioOutputAvailable() => available;

  @override
  Future<bool> beginAudioOutput({
    required String ownerId,
    String? reason,
  }) async {
    return available;
  }

  @override
  void endAudioOutput({required String ownerId, String? reason}) {}
}
