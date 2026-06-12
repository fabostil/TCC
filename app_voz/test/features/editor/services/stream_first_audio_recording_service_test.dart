import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_voz/features/editor/services/stream_first_audio_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  group('StreamFirstAudioRecordingService', () {
    late Directory tempDir;
    late _FakeStreamAudioRecorder recorder;
    late StreamFirstAudioRecordingService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'stream_first_recording_test_',
      );
      recorder = _FakeStreamAudioRecorder();
      service = StreamFirstAudioRecordingService(recorder: recorder);
    });

    tearDown(() async {
      await service.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('captura stream, publica chunks e grava arquivo WAV valido', () async {
      final rawChunks = <Uint8List>[];
      final rawDone = Completer<void>();
      service.rawAudioChunks.listen(rawChunks.add, onDone: rawDone.complete);

      final path = await service.startRecording('${tempDir.path}/take.m4a');
      recorder.emit(Uint8List.fromList([1, 2, 3, 4]));
      recorder.emit(Uint8List.fromList([5, 6]));

      final stoppedPath = await service.stopRecording();
      await rawDone.future;

      expect(path, '${tempDir.path}/take.wav');
      expect(stoppedPath, path);
      expect(recorder.lastConfig?.encoder, AudioEncoder.pcm16bits);
      expect(recorder.lastConfig?.sampleRate, 16000);
      expect(recorder.lastConfig?.numChannels, 1);
      expect(rawChunks.map((chunk) => chunk.toList()), [
        [1, 2, 3, 4],
        [5, 6],
      ]);

      final bytes = await File(path).readAsBytes();
      final data = ByteData.sublistView(bytes);
      expect(_ascii(bytes, 0, 4), 'RIFF');
      expect(_ascii(bytes, 8, 4), 'WAVE');
      expect(_ascii(bytes, 36, 4), 'data');
      expect(data.getUint32(4, Endian.little), 42);
      expect(data.getUint32(24, Endian.little), 16000);
      expect(data.getUint32(28, Endian.little), 32000);
      expect(data.getUint32(40, Endian.little), 6);
      expect(bytes.sublist(44), [1, 2, 3, 4, 5, 6]);
    });

    test('normaliza extensao para wav de forma previsivel', () {
      expect(
        service.wavPathForTesting('${tempDir.path}/take.m4a'),
        '${tempDir.path}/take.wav',
      );
      expect(
        service.wavPathForTesting('${tempDir.path}/take'),
        '${tempDir.path}/take.wav',
      );
    });

    test('pausa, retoma e cancela assinatura sem vazar listeners', () async {
      await service.startRecording('${tempDir.path}/take.m4a');

      await service.pauseRecording();
      await service.resumeRecording();
      await service.cancelRecording();

      expect(recorder.pauseCalls, 1);
      expect(recorder.resumeCalls, 1);
      expect(recorder.cancelCalls, 1);
      expect(recorder.controller.hasListener, isFalse);
    });
  });
}

class _FakeStreamAudioRecorder implements StreamAudioRecorder {
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast(sync: true);

  RecordConfig? lastConfig;
  bool permission = true;
  bool recording = false;
  bool paused = false;
  bool disposed = false;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int cancelCalls = 0;

  void emit(Uint8List chunk) {
    controller.add(chunk);
  }

  @override
  Future<bool> hasPermission({bool request = true}) async => permission;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    lastConfig = config;
    recording = true;
    return controller.stream;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    await controller.close();
    return null;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    paused = false;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    recording = false;
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: -24, max: -12);
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<bool> isPaused() async => paused;

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

String _ascii(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}
