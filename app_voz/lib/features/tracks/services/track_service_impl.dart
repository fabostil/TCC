import '../../editor/services/audio_player_service.dart';
import '../../editor/services/audio_recording_capture.dart';
import '../../editor/services/audio_recording_service.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/realtime/dispatch/handlers/recording_management_command_handler.dart';
import '../../voices/realtime/dispatch/handlers/track_command_handler.dart';
import '../../voices/realtime/nlu/voice_intent.dart';
import '../../voices/realtime/voice_realtime_event_bus.dart';
import '../../voices/realtime/voice_realtime_events.dart';

class TrackServiceImpl implements TrackService {
  TrackServiceImpl({
    AudioRecordingCapture? recordingCapture,
    AudioPlayerService? audioPlayerService,
    RecordingManagementCommandHandler? recordingManagementHandler,
    VoiceSessionManager? sessionManager,
    VoiceRealtimeEventBus? eventBus,
  }) : _sessionManager = sessionManager,
       _recordingCapture = recordingCapture,
       _audioPlayerService = audioPlayerService,
       _recordingManagementHandler = recordingManagementHandler,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  AudioRecordingCapture? _recordingCapture;
  AudioPlayerService? _audioPlayerService;
  final RecordingManagementCommandHandler? _recordingManagementHandler;
  final VoiceSessionManager? _sessionManager;
  final VoiceRealtimeEventBus _eventBus;

  VoiceSessionManager get _manager =>
      _sessionManager ?? VoiceSessionManager.instance;

  AudioRecordingCapture get _capture => _recordingCapture ??=
      AudioRecordingService(sessionManager: _manager, ownerId: 'track');

  AudioPlayerService get _player =>
      _audioPlayerService ??= AudioPlayerService(sessionManager: _manager);

  @override
  Future<void> startRecordingTrack({
    TrackIntent? intent,
    String? correlationId,
  }) async {
    final manager = _manager;
    if (manager.audioOwnerType != VoiceAudioOwnerType.none) {
      _publishFailure(
        intent: intent,
        correlationId: correlationId,
        reason: 'microphone_busy',
        metadata: {
          'activeOwnerId': manager.activeOwnerId,
          'audioOwnerType': manager.audioOwnerType.name,
        },
      );
      throw TrackCommandFailure(
        reason: 'microphone_busy',
        failureEventPublished: true,
      );
    }

    await _capture.startRecording();
  }

  @override
  Future<void> muteSelectedTrack({TrackIntent? intent, String? correlationId}) {
    return _player.stop();
  }

  @override
  Future<void> deleteSelectedTrack({
    TrackIntent? intent,
    String? correlationId,
  }) async {
    final handler = _recordingManagementHandler;
    if (handler == null) {
      throw TrackCommandFailure(reason: 'recording_delete_handler_missing');
    }

    await handler.handle(
      DeleteLastRecordingIntent(rawText: intent?.rawText ?? 'excluir faixa'),
      correlationId ?? 'track_delete_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _publishFailure({
    required TrackIntent? intent,
    required String? correlationId,
    required String reason,
    Map<String, Object?> metadata = const {},
  }) {
    _eventBus.publish(
      VoiceCommandFailedEvent(
        source: 'track_service_impl',
        reason: reason,
        correlationId: correlationId,
        intent: intent,
        metadata: metadata,
      ),
    );
  }
}
