import 'package:permission_handler/permission_handler.dart';

enum VoicePermissionResult { granted, denied, permanentlyDenied }

enum MicrophonePermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
}

abstract class MicrophonePermissionClient {
  Future<MicrophonePermissionStatus> status();

  Future<MicrophonePermissionStatus> request();

  Future<bool> openSettings();
}

class PermissionHandlerMicrophonePermissionClient
    implements MicrophonePermissionClient {
  const PermissionHandlerMicrophonePermissionClient();

  @override
  Future<MicrophonePermissionStatus> status() async {
    return _statusFromPlugin(await Permission.microphone.status);
  }

  @override
  Future<MicrophonePermissionStatus> request() async {
    return _statusFromPlugin(await Permission.microphone.request());
  }

  @override
  Future<bool> openSettings() {
    return openAppSettings();
  }

  MicrophonePermissionStatus _statusFromPlugin(PermissionStatus status) {
    if (status.isGranted) {
      return MicrophonePermissionStatus.granted;
    }

    if (status.isPermanentlyDenied) {
      return MicrophonePermissionStatus.permanentlyDenied;
    }

    if (status.isRestricted) {
      return MicrophonePermissionStatus.restricted;
    }

    if (status.isLimited) {
      return MicrophonePermissionStatus.limited;
    }

    return MicrophonePermissionStatus.denied;
  }
}

class VoicePermissionService {
  const VoicePermissionService({
    MicrophonePermissionClient client =
        const PermissionHandlerMicrophonePermissionClient(),
  }) : _client = client;

  const VoicePermissionService.test({
    required MicrophonePermissionClient client,
  }) : _client = client;

  final MicrophonePermissionClient _client;

  Future<VoicePermissionResult> requestMicrophone() async {
    final status = await _client.request();
    return _resultFromStatus(status);
  }

  Future<VoicePermissionResult> checkMicrophone() async {
    final status = await _client.status();
    return _resultFromStatus(status);
  }

  VoicePermissionResult _resultFromStatus(MicrophonePermissionStatus status) {
    if (status == MicrophonePermissionStatus.granted) {
      return VoicePermissionResult.granted;
    }

    if (status == MicrophonePermissionStatus.permanentlyDenied) {
      return VoicePermissionResult.permanentlyDenied;
    }

    return VoicePermissionResult.denied;
  }

  String guidanceMessage(VoicePermissionResult result) {
    return switch (result) {
      VoicePermissionResult.granted =>
        'Microfone liberado para comandos de voz.',
      VoicePermissionResult.denied =>
        'Permissão de microfone negada. O app continua funcionando em modo manual.',
      VoicePermissionResult.permanentlyDenied =>
        'Microfone bloqueado nas configurações do Android. Abra as permissões do app para reativar os comandos de voz.',
    };
  }

  bool shouldOpenSystemSettings(VoicePermissionResult result) {
    return result == VoicePermissionResult.permanentlyDenied;
  }

  Future<bool> openSystemSettings() {
    return _client.openSettings();
  }
}
