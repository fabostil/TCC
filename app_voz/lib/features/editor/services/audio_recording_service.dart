import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../voices/realtime/voice_realtime_events.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/coordination/voice_state_machine.dart';
import 'audio_recording_capture.dart';

class AudioRecordingService implements AudioRecordingCapture {
  AudioRecordingService({
    VoiceSessionManager? sessionManager,
    String ownerId = 'audio_recorder',
  }) : _sessionManager = sessionManager ?? VoiceSessionManager.instance,
       _ownerId = ownerId;

  final AudioRecorder _recorder = AudioRecorder();
  final VoiceSessionManager _sessionManager;
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
    _sessionManager.enterRecordingMode(
      ownerId: _ownerId,
      reason: 'audio_recorder_start',
    );

    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'record_permission_denied',
      );
      throw Exception('Permissao de microfone negada.');
    }

    final directory = await getApplicationDocumentsDirectory();
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
    } catch (_) {
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'record_start_failed',
      );
      rethrow;
    }

    _currentPath = filePath;
    return filePath;
  }

  @override
  Future<void> pauseRecording() async {
    final isRecording = await _recorder.isRecording();

    if (isRecording) {
      await _recorder.pause();
      _sessionManager.stateMachine.transitionTo(
        VoiceState.paused,
        ownerId: _ownerId,
        reason: 'record_pause',
        force: true,
      );
      _sessionManager.diagnostics.eventBus.publish(
        RecordingPausedEvent(
          source: 'audio_recording_service',
          ownerId: _ownerId,
          reason: 'record_pause',
        ),
      );
    }
  }

  @override
  Future<void> resumeRecording() async {
    final isPaused = await _recorder.isPaused();

    if (isPaused) {
      await _recorder.resume();
      _sessionManager.stateMachine.transitionTo(
        VoiceState.recording,
        ownerId: _ownerId,
        reason: 'record_resume',
        force: true,
      );
      _sessionManager.diagnostics.eventBus.publish(
        RecordingResumedEvent(
          source: 'audio_recording_service',
          ownerId: _ownerId,
          reason: 'record_resume',
        ),
      );
    }
  }

  @override
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _sessionManager.exitRecordingMode(
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
    _sessionManager.exitRecordingMode(
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
    _sessionManager.exitRecordingMode(
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
