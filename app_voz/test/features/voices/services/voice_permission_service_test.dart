import 'package:app_voz/features/voices/services/voice_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoicePermissionService', () {
    test(
      'checkMicrophone retorna granted quando permissao ja foi concedida',
      () async {
        final client = _FakeMicrophonePermissionClient(
          statusResult: MicrophonePermissionStatus.granted,
        );
        final service = VoicePermissionService.test(client: client);

        final result = await service.checkMicrophone();

        expect(result, VoicePermissionResult.granted);
        expect(client.statusCalls, 1);
        expect(client.requestCalls, 0);
        expect(client.openSettingsCalls, 0);
      },
    );

    test(
      'checkMicrophone retorna denied quando permissao esta negada',
      () async {
        final client = _FakeMicrophonePermissionClient(
          statusResult: MicrophonePermissionStatus.denied,
        );
        final service = VoicePermissionService.test(client: client);

        final result = await service.checkMicrophone();

        expect(result, VoicePermissionResult.denied);
        expect(client.statusCalls, 1);
        expect(client.requestCalls, 0);
      },
    );

    test(
      'requestMicrophone retorna granted quando request concede permissao',
      () async {
        final client = _FakeMicrophonePermissionClient(
          requestResult: MicrophonePermissionStatus.granted,
        );
        final service = VoicePermissionService.test(client: client);

        final result = await service.requestMicrophone();

        expect(result, VoicePermissionResult.granted);
        expect(client.statusCalls, 0);
        expect(client.requestCalls, 1);
      },
    );

    test(
      'requestMicrophone retorna denied quando request nega permissao',
      () async {
        final client = _FakeMicrophonePermissionClient(
          requestResult: MicrophonePermissionStatus.denied,
        );
        final service = VoicePermissionService.test(client: client);

        final result = await service.requestMicrophone();

        expect(result, VoicePermissionResult.denied);
        expect(client.requestCalls, 1);
      },
    );

    test(
      'checkMicrophone retorna permanentlyDenied quando permissao esta bloqueada',
      () async {
        final client = _FakeMicrophonePermissionClient(
          statusResult: MicrophonePermissionStatus.permanentlyDenied,
        );
        final service = VoicePermissionService.test(client: client);

        final result = await service.checkMicrophone();

        expect(result, VoicePermissionResult.permanentlyDenied);
        expect(service.shouldOpenSystemSettings(result), isTrue);
      },
    );

    test('restricted e limited seguem contrato atual como denied', () async {
      for (final status in [
        MicrophonePermissionStatus.restricted,
        MicrophonePermissionStatus.limited,
      ]) {
        final client = _FakeMicrophonePermissionClient(statusResult: status);
        final service = VoicePermissionService.test(client: client);

        expect(await service.checkMicrophone(), VoicePermissionResult.denied);
      }
    });

    test('openSystemSettings delega para client e retorna true', () async {
      final client = _FakeMicrophonePermissionClient(openSettingsResult: true);
      final service = VoicePermissionService.test(client: client);

      final result = await service.openSystemSettings();

      expect(result, isTrue);
      expect(client.openSettingsCalls, 1);
      expect(client.statusCalls, 0);
      expect(client.requestCalls, 0);
    });

    test('openSystemSettings delega para client e retorna false', () async {
      final client = _FakeMicrophonePermissionClient(openSettingsResult: false);
      final service = VoicePermissionService.test(client: client);

      final result = await service.openSystemSettings();

      expect(result, isFalse);
      expect(client.openSettingsCalls, 1);
    });

    test('checkMicrophone propaga erro ao consultar permissao', () {
      final error = StateError('status failed');
      final client = _FakeMicrophonePermissionClient(statusError: error);
      final service = VoicePermissionService.test(client: client);

      expect(service.checkMicrophone(), throwsA(same(error)));
    });

    test('requestMicrophone propaga erro ao solicitar permissao', () {
      final error = StateError('request failed');
      final client = _FakeMicrophonePermissionClient(requestError: error);
      final service = VoicePermissionService.test(client: client);

      expect(service.requestMicrophone(), throwsA(same(error)));
    });

    test('openSystemSettings propaga erro ao abrir configuracoes', () {
      final error = StateError('open settings failed');
      final client = _FakeMicrophonePermissionClient(openSettingsError: error);
      final service = VoicePermissionService.test(client: client);

      expect(service.openSystemSettings(), throwsA(same(error)));
    });

    test('mensagens de orientacao cobrem todos os resultados publicos', () {
      final service = VoicePermissionService.test(
        client: _FakeMicrophonePermissionClient(),
      );

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
        final service = VoicePermissionService.test(
          client: _FakeMicrophonePermissionClient(),
        );

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
  });
}

class _FakeMicrophonePermissionClient implements MicrophonePermissionClient {
  _FakeMicrophonePermissionClient({
    this.statusResult = MicrophonePermissionStatus.denied,
    this.requestResult = MicrophonePermissionStatus.denied,
    this.openSettingsResult = false,
    this.statusError,
    this.requestError,
    this.openSettingsError,
  });

  final MicrophonePermissionStatus statusResult;
  final MicrophonePermissionStatus requestResult;
  final bool openSettingsResult;
  final Object? statusError;
  final Object? requestError;
  final Object? openSettingsError;

  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<MicrophonePermissionStatus> status() async {
    statusCalls++;
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return statusResult;
  }

  @override
  Future<MicrophonePermissionStatus> request() async {
    requestCalls++;
    final error = requestError;
    if (error != null) {
      throw error;
    }
    return requestResult;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    final error = openSettingsError;
    if (error != null) {
      throw error;
    }
    return openSettingsResult;
  }
}
