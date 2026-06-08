import 'package:app_voz/features/voices/services/voice_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoicePermissionService', () {
    const service = VoicePermissionService();

    test('mensagens de orientacao cobrem todos os estados', () {
      expect(
        service.guidanceMessage(VoicePermissionResult.granted),
        contains('Microfone liberado'),
      );
      expect(
        service.guidanceMessage(VoicePermissionResult.denied),
        contains('modo manual'),
      );
      expect(
        service.guidanceMessage(VoicePermissionResult.permanentlyDenied),
        contains('configuracoes do Android'),
      );
    });

    test(
      'somente permissao bloqueada exige abrir configuracoes do sistema',
      () {
        expect(
          service.shouldOpenSystemSettings(VoicePermissionResult.granted),
          isFalse,
        );
        expect(
          service.shouldOpenSystemSettings(VoicePermissionResult.denied),
          isFalse,
        );
        expect(
          service.shouldOpenSystemSettings(
            VoicePermissionResult.permanentlyDenied,
          ),
          isTrue,
        );
      },
    );

    test(
      'checkMicrophone existe para verificacao imediata antes da captura',
      () {
        expect(
          service.checkMicrophone,
          isA<Future<VoicePermissionResult> Function()>(),
        );
      },
    );
  });
}
