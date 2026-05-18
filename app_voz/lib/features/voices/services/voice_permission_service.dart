import 'package:permission_handler/permission_handler.dart';

enum VoicePermissionResult { granted, denied, permanentlyDenied }

class VoicePermissionService {
  const VoicePermissionService();

  Future<VoicePermissionResult> requestMicrophone() async {
    final status = await Permission.microphone.request();

    if (status.isGranted) {
      return VoicePermissionResult.granted;
    }

    if (status.isPermanentlyDenied) {
      return VoicePermissionResult.permanentlyDenied;
    }

    return VoicePermissionResult.denied;
  }

  Future<bool> openSystemSettings() {
    return openAppSettings();
  }
}
