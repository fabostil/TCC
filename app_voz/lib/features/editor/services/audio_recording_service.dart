import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();

  String? _currentPath;

  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  Future<String> startRecording() async {
    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      throw Exception('Permissão de microfone negada.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory('${directory.path}/gravacoes');

    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }

    final fileName = 'gravacao_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = '${recordingsDirectory.path}/$fileName';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    _currentPath = filePath;
    return filePath;
  }

  Future<void> pauseRecording() async {
    final isRecording = await _recorder.isRecording();

    if (isRecording) {
      await _recorder.pause();
    }
  }

  Future<void> resumeRecording() async {
    final isPaused = await _recorder.isPaused();

    if (isPaused) {
      await _recorder.resume();
    }
  }

  Future<String?> stopRecording() async {
    final path = await _recorder.stop();

    if (path != null && path.isNotEmpty) {
      _currentPath = path;
      return path;
    }

    return _currentPath;
  }

  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _currentPath = null;
  }

  Future<Amplitude> getAmplitude() async {
    return _recorder.getAmplitude();
  }

  Future<bool> isRecording() async {
    return _recorder.isRecording();
  }

  Future<bool> isPaused() async {
    return _recorder.isPaused();
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
