import 'package:permission_handler/permission_handler.dart';

enum VoicePermissionResult { granted, denied, permanentlyDenied }

class VoicePermissionService {
  const VoicePermissionService();

  Future<VoicePermissionResult> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return _resultFromStatus(status);
  }

  Future<VoicePermissionResult> checkMicrophone() async {
    final status = await Permission.microphone.status;
    return _resultFromStatus(status);
  }

  VoicePermissionResult _resultFromStatus(PermissionStatus status) {
    if (status.isGranted) {
      return VoicePermissionResult.granted;
    }

    if (status.isPermanentlyDenied) {
      return VoicePermissionResult.permanentlyDenied;
    }

    return VoicePermissionResult.denied;
  }

  String guidanceMessage(VoicePermissionResult result) {
    return switch (result) {
      VoicePermissionResult.granted =>
        'Microfone liberado para comandos de voz.',
      VoicePermissionResult.denied =>
        'Permissao de microfone negada. O app continua funcionando em modo manual.',
      VoicePermissionResult.permanentlyDenied =>
        'Microfone bloqueado nas configuracoes do Android. Abra as permissoes do app para reativar os comandos de voz.',
    };
  }

  bool shouldOpenSystemSettings(VoicePermissionResult result) {
    return result == VoicePermissionResult.permanentlyDenied;
  }

  Future<bool> openSystemSettings() {
    return openAppSettings();
  }
}
