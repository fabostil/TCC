import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../voices/coordination/voice_diagnostics.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/coordination/voice_state_machine.dart';
import '../../voices/realtime/infrastructure/persistence/pcm_wav_file_writer.dart';
import '../../voices/realtime/voice_realtime_events.dart';
import 'audio_recording_capture.dart';

abstract class StreamAudioRecorder {
  Future<bool> hasPermission({bool request = true});
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<String?> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> cancel();
  Future<Amplitude> getAmplitude();
  Future<bool> isRecording();
  Future<bool> isPaused();
  Future<void> dispose();
}

class RecordStreamAudioRecorder implements StreamAudioRecorder {
  RecordStreamAudioRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission({bool request = true}) {
    return _recorder.hasPermission(request: request);
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) {
    return _recorder.startStream(config);
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

typedef PcmWavFileWriterFactory =
    Future<PcmWavFileWriter> Function(
      String filePath, {
      int sampleRate,
      int numChannels,
    });

class StreamFirstAudioRecordingService implements AudioRecordingCapture {
  StreamFirstAudioRecordingService({
    StreamAudioRecorder? recorder,
    VoiceSessionManager? sessionManager,
    PcmWavFileWriterFactory? writerFactory,
    String ownerId = 'stream_first_audio_recorder',
  }) : _recorder = recorder ?? RecordStreamAudioRecorder(),
       _sessionManager = sessionManager ?? VoiceSessionManager.instance,
       _writerFactory = writerFactory ?? PcmWavFileWriter.open,
       _ownerId = ownerId;

  static const int sampleRate = 16000;
  static const int numChannels = 1;

  final StreamAudioRecorder _recorder;
  final VoiceSessionManager _sessionManager;
  final PcmWavFileWriterFactory _writerFactory;
  final String _ownerId;

  StreamController<Uint8List> _rawAudioChunkController =
      StreamController<Uint8List>.broadcast(sync: true);
  StreamSubscription<Uint8List>? _chunkSubscription;
  PcmWavFileWriter? _writer;
  Completer<void>? _streamDoneCompleter;
  String? _currentPath;
  bool _disposed = false;

  @override
  Stream<Uint8List> get rawAudioChunks => _rawAudioChunkController.stream;

  String? get currentPath => _currentPath;

  @override
  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  @override
  Future<String> startRecording([String? filePath]) async {
    if (_disposed) {
      throw StateError('StreamFirstAudioRecordingService ja foi descartado.');
    }

    _ensureChunkController();
    _sessionManager.enterRecordingMode(
      ownerId: _ownerId,
      reason: 'stream_first_audio_recorder_start',
    );

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'record_permission_denied',
      );
      throw Exception('Permissao de microfone negada.');
    }

    final wavPath = filePath == null
        ? await _createDefaultWavPath()
        : _toWavPath(filePath);

    try {
      _writer = await _writerFactory(
        wavPath,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: numChannels,
        ),
      );
      _streamDoneCompleter = Completer<void>();
      _chunkSubscription = stream.listen(
        _handleChunk,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: true,
      );
      _currentPath = wavPath;
      return wavPath;
    } catch (error, stackTrace) {
      _sessionManager.diagnostics.record(
        VoiceDiagnosticEventType.error,
        ownerId: _ownerId,
        reason: 'stream_first_recording_start_failed',
        message: 'Stream-first recorder failed to start recording.',
        metadata: {
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
          'path': wavPath,
        },
      );
      await _cleanupAfterStartFailure();
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'stream_first_record_start_failed',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> pauseRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.pause();
      _sessionManager.stateMachine.transitionTo(
        VoiceState.paused,
        ownerId: _ownerId,
        reason: 'stream_first_record_pause',
        force: true,
      );
      _sessionManager.diagnostics.eventBus.publish(
        RecordingPausedEvent(
          source: 'stream_first_audio_recording_service',
          ownerId: _ownerId,
          reason: 'stream_first_record_pause',
        ),
      );
    }
  }

  @override
  Future<void> resumeRecording() async {
    if (await _recorder.isPaused()) {
      await _recorder.resume();
      _sessionManager.stateMachine.transitionTo(
        VoiceState.recording,
        ownerId: _ownerId,
        reason: 'stream_first_record_resume',
        force: true,
      );
      _sessionManager.diagnostics.eventBus.publish(
        RecordingResumedEvent(
          source: 'stream_first_audio_recording_service',
          ownerId: _ownerId,
          reason: 'stream_first_record_resume',
        ),
      );
    }
  }

  @override
  Future<String?> stopRecording() async {
    final path = _currentPath;
    try {
      await _recorder.stop();
      await _waitForStreamDone();
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      await _writer?.flushAndClose();
      _writer = null;
      await _closeChunkController();
      return path;
    } finally {
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'stream_first_audio_recorder_stop',
      );
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      await _recorder.cancel();
    } finally {
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      await _writer?.flushAndClose();
      _writer = null;
      _currentPath = null;
      await _closeChunkController();
      _sessionManager.exitRecordingMode(
        ownerId: _ownerId,
        reason: 'stream_first_audio_recorder_cancel',
      );
    }
  }

  @override
  Future<Amplitude> getAmplitude() => _recorder.getAmplitude();

  @override
  Future<bool> isRecording() => _recorder.isRecording();

  @override
  Future<bool> isPaused() => _recorder.isPaused();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    await _chunkSubscription?.cancel();
    _chunkSubscription = null;
    await _writer?.flushAndClose();
    _writer = null;
    await _closeChunkController();
    _sessionManager.exitRecordingMode(
      ownerId: _ownerId,
      reason: 'stream_first_audio_recorder_dispose',
    );
    await _recorder.dispose();
  }

  void _handleChunk(Uint8List chunk) {
    if (!_rawAudioChunkController.isClosed) {
      _rawAudioChunkController.add(chunk);
    }
    _writer?.writeChunk(chunk);
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _sessionManager.diagnostics.record(
      VoiceDiagnosticEventType.error,
      ownerId: _ownerId,
      reason: 'stream_first_recording_stream_failed',
      message: 'Stream-first recorder received a stream error.',
      metadata: {
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        'path': _currentPath,
      },
    );
    if (!_rawAudioChunkController.isClosed) {
      _rawAudioChunkController.addError(error, stackTrace);
    }
    _completeStreamDone();
  }

  void _handleStreamDone() {
    _completeStreamDone();
  }

  void _completeStreamDone() {
    final completer = _streamDoneCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _waitForStreamDone() async {
    final completer = _streamDoneCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    try {
      await completer.future.timeout(const Duration(milliseconds: 500));
    } catch (error, stackTrace) {
      _sessionManager.diagnostics.record(
        VoiceDiagnosticEventType.error,
        ownerId: _ownerId,
        reason: 'stream_first_recording_wait_done_failed',
        message: 'Stream-first recorder stream completion wait failed.',
        metadata: {
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
          'path': _currentPath,
        },
      );
    }
  }

  Future<void> _cleanupAfterStartFailure() async {
    await _chunkSubscription?.cancel();
    _chunkSubscription = null;
    await _writer?.flushAndClose();
    _writer = null;
  }

  void _ensureChunkController() {
    if (_rawAudioChunkController.isClosed) {
      _rawAudioChunkController = StreamController<Uint8List>.broadcast(
        sync: true,
      );
    }
  }

  Future<void> _closeChunkController() async {
    if (!_rawAudioChunkController.isClosed) {
      await _rawAudioChunkController.close();
    }
  }

  Future<String> _createDefaultWavPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory('${directory.path}/gravacoes');
    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }
    return '${recordingsDirectory.path}/gravacao_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  String _toWavPath(String filePath) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(filePath, 'filePath', 'caminho vazio');
    }

    final dot = trimmed.lastIndexOf('.');
    final separator = trimmed.lastIndexOf(Platform.pathSeparator);
    if (dot > separator) {
      return '${trimmed.substring(0, dot)}.wav';
    }
    return '$trimmed.wav';
  }

  @visibleForTesting
  String wavPathForTesting(String filePath) => _toWavPath(filePath);
}
