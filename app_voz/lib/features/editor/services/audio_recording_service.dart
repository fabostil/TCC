import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../voices/coordination/voice_diagnostics.dart';
import '../../voices/realtime/voice_realtime_events.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/coordination/voice_state_machine.dart';
import 'audio_recording_capture.dart';

abstract class AudioRecorderClient {
  Future<bool> hasPermission();

  Future<void> start(RecordConfig config, {required String path});

  Future<String?> stop();

  Future<void> pause();

  Future<void> resume();

  Future<void> cancel();

  Future<Amplitude> getAmplitude();

  Future<bool> isRecording();

  Future<bool> isPaused();

  Future<void> dispose();
}

class RecordAudioRecorderClient implements AudioRecorderClient {
  RecordAudioRecorderClient({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(RecordConfig config, {required String path}) {
    return _recorder.start(config, path: path);
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<Amplitude> getAmplitude() => _recorder.getAmplitude();

  @override
  Future<bool> isRecording() => _recorder.isRecording();

  @override
  Future<bool> isPaused() => _recorder.isPaused();

  @override
  Future<void> dispose() => _recorder.dispose();
}

abstract class AudioRecordingSessionClient {
  void enterRecordingMode({required String ownerId, required String reason});

  void exitRecordingMode({required String ownerId, required String reason});

  void transitionToPaused({required String ownerId, required String reason});

  void transitionToRecording({required String ownerId, required String reason});

  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  });

  void publishPaused({required String ownerId, required String reason});

  void publishResumed({required String ownerId, required String reason});
}

class VoiceSessionAudioRecordingClient implements AudioRecordingSessionClient {
  const VoiceSessionAudioRecordingClient(this._sessionManager);

  final VoiceSessionManager _sessionManager;

  @override
  void enterRecordingMode({required String ownerId, required String reason}) {
    _sessionManager.enterRecordingMode(ownerId: ownerId, reason: reason);
  }

  @override
  void exitRecordingMode({required String ownerId, required String reason}) {
    _sessionManager.exitRecordingMode(ownerId: ownerId, reason: reason);
  }

  @override
  void transitionToPaused({required String ownerId, required String reason}) {
    _sessionManager.stateMachine.transitionTo(
      VoiceState.paused,
      ownerId: ownerId,
      reason: reason,
      force: true,
    );
  }

  @override
  void transitionToRecording({
    required String ownerId,
    required String reason,
  }) {
    _sessionManager.stateMachine.transitionTo(
      VoiceState.recording,
      ownerId: ownerId,
      reason: reason,
      force: true,
    );
  }

  @override
  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  }) {
    _sessionManager.diagnostics.record(
      VoiceDiagnosticEventType.error,
      ownerId: ownerId,
      reason: 'audio_recording_start_failed',
      message: 'Audio recorder failed to start recording.',
      metadata: {
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        'path': path,
      },
    );
  }

  @override
  void publishPaused({required String ownerId, required String reason}) {
    _sessionManager.diagnostics.eventBus.publish(
      RecordingPausedEvent(
        source: 'audio_recording_service',
        ownerId: ownerId,
        reason: reason,
      ),
    );
  }

  @override
  void publishResumed({required String ownerId, required String reason}) {
    _sessionManager.diagnostics.eventBus.publish(
      RecordingResumedEvent(
        source: 'audio_recording_service',
        ownerId: ownerId,
        reason: reason,
      ),
    );
  }
}

typedef DocumentsDirectoryProvider = Future<Directory> Function();

class AudioRecordingService implements AudioRecordingCapture {
  AudioRecordingService({
    VoiceSessionManager? sessionManager,
    AudioRecorderClient? recorder,
    AudioRecordingSessionClient? sessionClient,
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    String ownerId = 'audio_recorder',
  }) : _recorder = recorder ?? RecordAudioRecorderClient(),
       _sessionClient =
           sessionClient ??
           VoiceSessionAudioRecordingClient(
             sessionManager ?? VoiceSessionManager.instance,
           ),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _ownerId = ownerId;

  AudioRecordingService.test({
    required AudioRecorderClient recorder,
    required AudioRecordingSessionClient sessionClient,
    required DocumentsDirectoryProvider documentsDirectoryProvider,
    String ownerId = 'audio_recorder',
  }) : _recorder = recorder,
       _sessionClient = sessionClient,
       _documentsDirectoryProvider = documentsDirectoryProvider,
       _ownerId = ownerId;

  final AudioRecorderClient _recorder;
  final AudioRecordingSessionClient _sessionClient;
  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final String _ownerId;
  final StreamController<Uint8List> _rawAudioChunkController =
      StreamController<Uint8List>.broadcast(sync: true);

  String? _currentPath;
  bool _disposed = false;

  @override
  Stream<Uint8List> get rawAudioChunks => _rawAudioChunkController.stream;

  @override
  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  @override
  Future<String> startRecording() async {
    _sessionClient.enterRecordingMode(
      ownerId: _ownerId,
      reason: 'audio_recorder_start',
    );

    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      _sessionClient.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'record_permission_denied',
      );
      throw Exception('Permissão de microfone negada.');
    }

    final directory = await _documentsDirectoryProvider();
    final recordingsDirectory = Directory('${directory.path}/gravacoes');

    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }

    final fileName = 'gravacao_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = '${recordingsDirectory.path}/$fileName';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
    } catch (error, stackTrace) {
      _sessionClient.recordStartFailure(
        ownerId: _ownerId,
        error: error,
        stackTrace: stackTrace,
        path: filePath,
      );
      _sessionClient.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'record_start_failed',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    _currentPath = filePath;
    return filePath;
  }

  @override
  Future<void> pauseRecording() async {
    final isRecording = await _recorder.isRecording();

    if (isRecording) {
      await _recorder.pause();
      _sessionClient.transitionToPaused(
        ownerId: _ownerId,
        reason: 'record_pause',
      );
      _sessionClient.publishPaused(ownerId: _ownerId, reason: 'record_pause');
    }
  }

  @override
  Future<void> resumeRecording() async {
    final isPaused = await _recorder.isPaused();

    if (isPaused) {
      await _recorder.resume();
      _sessionClient.transitionToRecording(
        ownerId: _ownerId,
        reason: 'record_resume',
      );
      _sessionClient.publishResumed(ownerId: _ownerId, reason: 'record_resume');
    }
  }

  @override
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _sessionClient.exitRecordingMode(
      ownerId: _ownerId,
      reason: 'audio_recorder_stop',
    );

    if (path != null && path.isNotEmpty) {
      _currentPath = path;
      return path;
    }

    return _currentPath;
  }

  @override
  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _currentPath = null;
    _sessionClient.exitRecordingMode(
      ownerId: _ownerId,
      reason: 'audio_recorder_cancel',
    );
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return _recorder.getAmplitude();
  }

  @override
  Future<bool> isRecording() async {
    return _recorder.isRecording();
  }

  @override
  Future<bool> isPaused() async {
    return _recorder.isPaused();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    await _rawAudioChunkController.close();
    _sessionClient.exitRecordingMode(
      ownerId: _ownerId,
      reason: 'audio_recorder_dispose',
    );
    await _recorder.dispose();
  }

  @visibleForTesting
  void publishRawAudioChunkForTesting(Uint8List chunk) {
    if (!_rawAudioChunkController.isClosed) {
      _rawAudioChunkController.add(chunk);
    }
  }
}
