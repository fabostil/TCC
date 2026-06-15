import 'package:app_voz/features/voices/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeechResultGate', () {
    test('resultado parcial nao executa comando', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('reproduzir', isFinal: false, onResult: delivered.add);

      expect(delivered, isEmpty);
    });

    test('resultado final completo executa uma unica vez', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('reproduzir', isFinal: false, onResult: delivered.add);
      gate.add('reproduzir gravação 2', isFinal: true, onResult: delivered.add);
      gate.add('reproduzir gravação 2', isFinal: true, onResult: delivered.add);

      expect(delivered, ['reproduzir gravação 2']);
    });

    test(
      'status finaliza ultimo parcial quando plataforma nao marca final',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('voltar', isFinal: false, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['voltar']);
      },
    );

    test('parcial descartado por erro nao e executado no encerramento', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('inicio', isFinal: false, onResult: delivered.add);
      gate.clearPending();
      gate.finalizePending(delivered.add);

      expect(delivered, isEmpty);
    });

    test('comando duplicado proximo nao executa em nova sessao', () {
      var now = DateTime(2026, 6, 15, 10);
      final delivered = <String>[];
      final gate = SpeechResultGate(now: () => now);

      gate.add('dashboard', isFinal: true, onResult: delivered.add);
      gate.clearPending();
      now = now.add(const Duration(seconds: 1));
      gate.add('dashboard', isFinal: true, onResult: delivered.add);

      expect(delivered, ['dashboard']);
    });
  });
}
