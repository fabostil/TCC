import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/editor/controllers/recording_realtime_coordinator.dart';
import 'package:app_voz/features/editor/services/audio_recording_capture.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingRealtimeCoordinator', () {
    test('usa path retornado pelo stop como fonte da verdade', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.wav',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
      );
      String? finalizedPath;

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              finalizedPath = path;
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(coordinator.state.currentPath, '/tmp/take.m4a');

      final saved = await coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              finalizedPath = path;
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(finalizedPath, '/tmp/take.wav');
      expect(saved?.caminhoArquivo, '/tmp/take.wav');
      expect(coordinator.state.currentPath, isNull);
      expect(recordingService.stopCalls, 1);

      coordinator.dispose();
    });
  });
}

class _FakeAudioRecordingCapture implements AudioRecordingCapture {
  _FakeAudioRecordingCapture({required this.startPath, required this.stopPath});

  final String startPath;
  final String stopPath;
  final StreamController<Uint8List> _chunks =
      StreamController<Uint8List>.broadcast(sync: true);

  int stopCalls = 0;
  bool recording = false;
  bool paused = false;

  @override
  Stream<Uint8List> get rawAudioChunks => _chunks.stream;

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> dispose() async {
    await _chunks.close();
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: -24, max: -12);
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isPaused() async => paused;

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<void> pauseRecording() async {
    paused = true;
  }

  @override
  Future<void> resumeRecording() async {
    paused = false;
  }

  @override
  Future<String> startRecording() async {
    recording = true;
    return startPath;
  }

  @override
  Future<String?> stopRecording() async {
    stopCalls += 1;
    recording = false;
    return stopPath;
  }
}
