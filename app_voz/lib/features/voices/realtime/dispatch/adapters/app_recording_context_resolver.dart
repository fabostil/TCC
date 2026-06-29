import '../../../../../models/gravacao.dart';
import '../../../../recordings/services/recording_management_service.dart';
import '../contracts/voice_session_context_holder.dart';
import '../contracts/voice_recording_context_resolver.dart';

class AppRecordingContextResolver implements VoiceRecordingContextResolver {
  const AppRecordingContextResolver({
    required RecordingManagementService recordingService,
    required VoiceSessionContextHolder contextHolder,
    String? Function()? activeSessionTokenProvider,
  }) : _recordingService = recordingService,
       _contextHolder = contextHolder,
       _activeSessionTokenProvider = activeSessionTokenProvider;

  final RecordingManagementService _recordingService;
  final VoiceSessionContextHolder _contextHolder;
  final String? Function()? _activeSessionTokenProvider;

  @override
  Future<Gravacao?> resolveLastRecording() async {
    final contextSessionToken = _contextHolder.activeSessionToken;
    final activeSessionToken = _activeSessionTokenProvider?.call();
    if (contextSessionToken == null ||
        activeSessionToken == null ||
        contextSessionToken != activeSessionToken) {
      return null;
    }

    final projetoId = _parseId(_contextHolder.currentProjectId);
    if (projetoId == null) {
      return null;
    }

    final recordings = await _recordingService.listByProjectWithFileState(
      projetoId,
    );
    return recordings.isEmpty ? null : recordings.first;
  }

  int? _parseId(String? value) {
    if (value == null) {
      return null;
    }

    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}
