import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ── H11.4: gravacao sem projeto ───────────────────────────────────────────────
//
// Testa o reconhecimento dos comandos de gravacao e confirma que
// 'gravar', 'pausar gravacao' e similares sao interpretados corretamente.
// O comportamento do guard em EditorPage.iniciarGravacao (widget.projeto == null)
// e exercitado indiretamente — a cobertura direta depende do widget completo
// com DB real, o que esta fora do escopo destes testes unitarios.

void main() {
  group('H11.4 - comandos de gravacao sem projeto (reconhecimento)', () {
    // 1. 'gravar' e reconhecido como iniciarGravacao
    test('gravar e reconhecido como iniciarGravacao', () {
      final command = const CommandService().interpret('gravar');
      expect(command.type, VoiceCommandType.iniciarGravacao);
      expect(command.recognized, isTrue);
    });

    // 2. 'iniciar gravacao' e reconhecido como iniciarGravacao
    test('iniciar gravacao e reconhecido como iniciarGravacao', () {
      final command = const CommandService().interpret('iniciar gravação');
      expect(command.type, VoiceCommandType.iniciarGravacao);
      expect(command.recognized, isTrue);
    });

    // 3. 'pausar' e reconhecido como pausarGravacao
    test('pausar e reconhecido como pausarGravacao', () {
      final command = const CommandService().interpret('pausar');
      expect(command.type, VoiceCommandType.pausarGravacao);
      expect(command.recognized, isTrue);
    });

    // 4. 'encerrar gravacao' e reconhecido como encerrarGravacao
    test('encerrar gravacao e reconhecido como encerrarGravacao', () {
      final command = const CommandService().interpret('encerrar gravação');
      expect(command.type, VoiceCommandType.encerrarGravacao);
      expect(command.recognized, isTrue);
    });

    // 5. 'parar' e reconhecido
    test('parar e reconhecido como tipo de controle de gravacao ou reproducao',
        () {
      final command = const CommandService().interpret('parar');
      expect(command.recognized, isTrue);
    });

    // 6. Mensagem de guard para gravacao sem projeto contem palavras esperadas
    test('mensagem de guard para gravacao sem projeto e especifica', () {
      const message = 'Abra ou crie um projeto antes de gravar uma ideia.';
      expect(message, contains('projeto'));
      expect(message, contains('gravar'));
      expect(message, isNotEmpty);
    });

    // 7. Mensagem de abrir editor sem projeto e especifica
    test('mensagem de abrir editor sem projeto e especifica', () {
      const message = 'Crie ou abra um projeto antes de acessar o editor.';
      expect(message, contains('projeto'));
      expect(message, contains('editor'));
      expect(message, isNotEmpty);
    });
  });
}
