import 'dart:typed_data';

import 'package:record/record.dart';

abstract class AudioRecordingCapture {
  Stream<Uint8List> get rawAudioChunks;

  Future<bool> hasPermission();
  Future<String> startRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<String?> stopRecording();
  Future<void> cancelRecording();
  Future<Amplitude> getAmplitude();
  Future<bool> isRecording();
  Future<bool> isPaused();
  Future<void> dispose();
}
