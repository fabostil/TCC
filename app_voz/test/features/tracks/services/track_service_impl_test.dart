import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/editor/services/audio_player_service.dart';
import 'package:app_voz/features/editor/services/audio_recording_capture.dart';
import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/features/tracks/services/track_service_impl.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/recording_management_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/track_command_handler.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackServiceImpl', () {
    late VoiceSessionManager sessionManager;
    late VoiceRealtimeEventBus eventBus;
    late _FakeAudioRecordingCapture recordingCapture;
    late _FakeAudioPlayerService audioPlayerService;

    setUp(() {
      sessionManager = VoiceSessionManager.instance;
      sessionManager.resetForTesting();
      eventBus = VoiceRealtimeEventBus();
      recordingCapture = _FakeAudioRecordingCapture();
      audioPlayerService = _FakeAudioPlayerService();
    });

    tearDown(() async {
      sessionManager.resetForTesting();
      await audioPlayerService.dispose();
      await recordingCapture.dispose();
    });

    test('inicia gravacao de faixa quando microfone esta livre', () async {
      final service = TrackServiceImpl(
        recordingCapture: recordingCapture,
        audioPlayerService: audioPlayerService,
        sessionManager: sessionManager,
        eventBus: eventBus,
      );

      await service.startRecordingTrack(
        intent: const TrackIntent(action: 'record', rawText: 'gravar faixa'),
        correlationId: 'track-record',
      );

      expect(recordingCapture.startCalls, 1);
    });

    test('publica microphone_busy quando microfone esta ocupado', () async {
      sessionManager.claimListening('home');
      final service = TrackServiceImpl(
        recordingCapture: recordingCapture,
        audioPlayerService: audioPlayerService,
        sessionManager: sessionManager,
        eventBus: eventBus,
      );

      await expectLater(
        service.startRecordingTrack(
          intent: const TrackIntent(action: 'record', rawText: 'gravar faixa'),
          correlationId: 'track-record',
        ),
        throwsA(isA<TrackCommandFailure>()),
      );

      expect(recordingCapture.startCalls, 0);
      final failed = eventBus.timeline
          .whereType<VoiceCommandFailedEvent>()
          .single;
      expect(failed.reason, 'microphone_busy');
      expect(failed.correlationId, 'track-record');
      expect(failed.metadata['audioOwnerType'], 'stt');
    });

    test('muteSelectedTrack para playback atual', () async {
      final service = TrackServiceImpl(
        recordingCapture: recordingCapture,
        audioPlayerService: audioPlayerService,
        sessionManager: sessionManager,
        eventBus: eventBus,
      );

      await service.muteSelectedTrack(
        intent: const TrackIntent(action: 'mute', rawText: 'mutar faixa'),
        correlationId: 'track-mute',
      );

      expect(audioPlayerService.stopCalls, 1);
    });

    test('deleteSelectedTrack delega ao fluxo confirmavel existente', () async {
      final deleteHandler = _FakeRecordingManagementCommandHandler();
      final service = TrackServiceImpl(
        recordingCapture: recordingCapture,
        audioPlayerService: audioPlayerService,
        recordingManagementHandler: deleteHandler,
        sessionManager: sessionManager,
        eventBus: eventBus,
      );

      await service.deleteSelectedTrack(
        intent: const TrackIntent(action: 'delete', rawText: 'excluir faixa'),
        correlationId: 'track-delete',
      );

      expect(deleteHandler.intents.single, isA<DeleteLastRecordingIntent>());
      expect(deleteHandler.intents.single.rawText, 'excluir faixa');
      expect(deleteHandler.correlationIds.single, 'track-delete');
    });
  });
}

class _FakeAudioRecordingCapture implements AudioRecordingCapture {
  final StreamController<Uint8List> _chunks =
      StreamController<Uint8List>.broadcast(sync: true);
  var startCalls = 0;

  @override
  Stream<Uint8List> get rawAudioChunks => _chunks.stream;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {
    await _chunks.close();
  }

  @override
  Future<Amplitude> getAmplitude() async => Amplitude(current: -24, max: -12);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isPaused() async => false;

  @override
  Future<bool> isRecording() async => startCalls > 0;

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Future<String> startRecording() async {
    startCalls += 1;
    return 'track.m4a';
  }

  @override
  Future<String?> stopRecording() async => 'track.m4a';
}

class _FakeAudioPlayerService extends AudioPlayerService {
  _FakeAudioPlayerService() : super();

  final StreamController<PlayerState> _playerStates =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durations =
      StreamController<Duration?>.broadcast(sync: true);
  var stopCalls = 0;

  @override
  bool get isPlaying => false;

  @override
  String? get currentPath => 'track.m4a';

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    await _playerStates.close();
    await _positions.close();
    await _durations.close();
    await super.dispose();
  }
}

class _FakeRecordingManagementCommandHandler
    extends RecordingManagementCommandHandler {
  _FakeRecordingManagementCommandHandler()
    : super(recordingService: RecordingManagementService());

  final List<VoiceIntent> intents = [];
  final List<String> correlationIds = [];

  @override
  Future<void> handle(VoiceIntent intent, String correlationId) async {
    intents.add(intent);
    correlationIds.add(correlationId);
  }
}
