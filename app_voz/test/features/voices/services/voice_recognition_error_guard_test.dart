import 'package:app_voz/features/voices/services/voice_recognition_error_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceRecognitionErrorGuard', () {
    test('suprime erros iguais dentro do cooldown', () {
      var now = DateTime(2026, 6, 15, 10);
      final guard = VoiceRecognitionErrorGuard(now: () => now);

      final first = guard.evaluate('error_speech_timeout');
      now = now.add(const Duration(seconds: 2));
      final repeated = guard.evaluate('error_speech_timeout');

      expect(first.shouldPresent, isTrue);
      expect(first.shouldRecover, isTrue);
      expect(repeated.shouldPresent, isFalse);
      expect(repeated.shouldRecover, isFalse);
    });

    test('suprime codigos diferentes que exibiriam a mesma mensagem', () {
      var now = DateTime(2026, 6, 15, 10);
      final guard = VoiceRecognitionErrorGuard(now: () => now);

      guard.evaluate('error_speech_timeout');
      now = now.add(const Duration(seconds: 1));
      final startFailure = guard.evaluate('start_failed');

      expect(startFailure.shouldPresent, isFalse);
      expect(startFailure.shouldRecover, isFalse);
    });

    test('permite informar novamente depois do cooldown', () {
      var now = DateTime(2026, 6, 15, 10);
      final guard = VoiceRecognitionErrorGuard(now: () => now);

      guard.evaluate('error_network');
      now = now.add(const Duration(seconds: 9));

      expect(guard.evaluate('error_network').shouldPresent, isTrue);
    });

    test('mensagem publica e amigavel e nao contem termo tecnico', () {
      expect(
        VoiceRecognitionErrorGuard.friendlyMessage,
        'Não consegui ouvir o comando agora. '
        'Tente novamente em alguns segundos.',
      );
      expect(
        VoiceRecognitionErrorGuard.friendlyMessage,
        isNot(contains('reconhecimento de voz')),
      );
      expect(
        VoiceRecognitionErrorGuard.friendlyMessage,
        isNot(contains('PlatformException')),
      );
    });
  });
}
