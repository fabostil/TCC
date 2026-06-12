import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/vad/adaptive_silence_vad.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/wakeword/wake_word_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WakeWordVadGate', () {
    test(
      'em silencio estavel amostra wake-word sem processar todos os frames',
      () {
        final vad = AdaptiveSilenceVad();
        final gate = WakeWordVadGate(
          maxHangoverFrames: 0,
          stableSilenceSampleIntervalFrames: 5,
        );
        final engine = _CountingWakeWordEngine();
        final silenceFrame = _pcm16Frame(
          sampleCount: vad.frameSizeBytes ~/ 2,
          sampleValue: 0,
        );

        for (var i = 0; i < 10; i += 1) {
          _processFrame(
            vad: vad,
            gate: gate,
            engine: engine,
            frame: silenceFrame,
          );
        }

        expect(engine.processFrameCalls, 2);
      },
    );

    test('reativa imediatamente quando um frame sai do silencio estavel', () {
      final vad = AdaptiveSilenceVad();
      final gate = WakeWordVadGate(
        maxHangoverFrames: 2,
        stableSilenceSampleIntervalFrames: 5,
      );
      final engine = _CountingWakeWordEngine();
      final silenceFrame = _pcm16Frame(
        sampleCount: vad.frameSizeBytes ~/ 2,
        sampleValue: 0,
      );
      final activeFrame = _pcm16Frame(
        sampleCount: vad.frameSizeBytes ~/ 2,
        sampleValue: 2000,
      );

      for (var i = 0; i < 4; i += 1) {
        _processFrame(
          vad: vad,
          gate: gate,
          engine: engine,
          frame: silenceFrame,
        );
      }
      expect(engine.processFrameCalls, 1);

      _processFrame(vad: vad, gate: gate, engine: engine, frame: activeFrame);

      expect(engine.processFrameCalls, 2);

      _processFrame(vad: vad, gate: gate, engine: engine, frame: silenceFrame);

      expect(engine.processFrameCalls, 3);
    });

    test(
      'wake-word em frame amostrado reabre hangover sem aguardar novo ruido',
      () {
        final vad = AdaptiveSilenceVad();
        final gate = WakeWordVadGate(
          maxHangoverFrames: 2,
          stableSilenceSampleIntervalFrames: 2,
        );
        final engine = _CountingWakeWordEngine(detectOnCall: 1);
        final silenceFrame = _pcm16Frame(
          sampleCount: vad.frameSizeBytes ~/ 2,
          sampleValue: 0,
        );

        _processFrame(
          vad: vad,
          gate: gate,
          engine: engine,
          frame: silenceFrame,
        );
        expect(engine.processFrameCalls, 1);

        _processFrame(
          vad: vad,
          gate: gate,
          engine: engine,
          frame: silenceFrame,
        );
        expect(engine.processFrameCalls, 2);

        _processFrame(
          vad: vad,
          gate: gate,
          engine: engine,
          frame: silenceFrame,
        );
        _processFrame(
          vad: vad,
          gate: gate,
          engine: engine,
          frame: silenceFrame,
        );

        expect(engine.processFrameCalls, 3);
      },
    );
  });
}

void _processFrame({
  required AdaptiveSilenceVad vad,
  required WakeWordVadGate gate,
  required _CountingWakeWordEngine engine,
  required Uint8List frame,
}) {
  final result = vad.analyzeFrame(frame);
  if (!gate.shouldProcessWakeWord(result)) {
    return;
  }

  final detected = engine.processFrame(_pcm16LittleEndianFrame(frame));
  if (detected) {
    gate.reopenAfterWakeWordDetection();
  }
}

Uint8List _pcm16Frame({required int sampleCount, required int sampleValue}) {
  final frame = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(frame);
  for (var i = 0; i < sampleCount; i += 1) {
    data.setInt16(i * 2, sampleValue, Endian.little);
  }
  return frame;
}

Int16List _pcm16LittleEndianFrame(Uint8List frame) {
  final sampleCount = frame.length ~/ 2;
  final samples = Int16List(sampleCount);
  final data = ByteData.sublistView(frame);
  for (var i = 0; i < sampleCount; i += 1) {
    samples[i] = data.getInt16(i * 2, Endian.little);
  }
  return samples;
}

class _CountingWakeWordEngine implements WakeWordEngine {
  _CountingWakeWordEngine({this.detectOnCall});

  final int? detectOnCall;
  int processFrameCalls = 0;

  @override
  Future<void> init({
    String? accessKey,
    String? modelPath,
    required String keywordPath,
    required double sensitivity,
  }) async {}

  @override
  bool processFrame(Int16List frame) {
    processFrameCalls += 1;
    return detectOnCall == processFrameCalls;
  }

  @override
  Future<void> dispose() async {}
}
