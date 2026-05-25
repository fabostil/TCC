import '../../../../../models/gravacao.dart';
import '../../../../recordings/services/recording_management_service.dart';
import '../contracts/voice_recording_context_resolver.dart';

typedef VoiceRecordingScopeValue = int? Function();

class AppRecordingContextResolver implements VoiceRecordingContextResolver {
  const AppRecordingContextResolver({
    required RecordingManagementService recordingService,
    VoiceRecordingScopeValue? usuarioIdProvider,
    VoiceRecordingScopeValue? projetoIdProvider,
  }) : _recordingService = recordingService,
       _usuarioIdProvider = usuarioIdProvider,
       _projetoIdProvider = projetoIdProvider;

  final RecordingManagementService _recordingService;
  final VoiceRecordingScopeValue? _usuarioIdProvider;
  final VoiceRecordingScopeValue? _projetoIdProvider;

  @override
  Future<Gravacao?> resolveLastRecording() async {
    final projetoId = _projetoIdProvider?.call();
    if (projetoId != null) {
      final recordings = await _recordingService.listByProjectWithFileState(
        projetoId,
      );
      return recordings.isEmpty ? null : recordings.first;
    }

    final usuarioId = _usuarioIdProvider?.call();
    if (usuarioId != null) {
      final recordings = await _recordingService.listByUserWithFileState(
        usuarioId,
      );
      return recordings.isEmpty ? null : recordings.first;
    }

    return null;
  }
}
