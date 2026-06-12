import 'dart:ffi';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/wakeword/picovoice_porcupine_engine.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/wakeword/wake_word_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PicovoicePorcupineEngine fallback', () {
    test(
      'usa StubWakeWordEngine quando biblioteca nativa nao carrega',
      () async {
        final engine = PicovoicePorcupineEngine(
          libraryLoader: () =>
              throw ArgumentError('missing libpv_porcupine.so'),
        );

        await engine.init(
          accessKey: 'test-access-key',
          modelPath: 'model.pv',
          keywordPath: 'keyword.ppn',
          sensitivity: 0.5,
        );

        expect(engine.processFrame(_magicFrame()), isTrue);

        await engine.dispose();
        expect(engine.processFrame(_magicFrame()), isFalse);
      },
    );

    test(
      'dispose e seguro quando init nativo falha antes de criar ponteiro',
      () async {
        final engine = PicovoicePorcupineEngine(
          libraryLoader: () =>
              DynamicLibrary.open('libpv_porcupine_missing.so'),
        );

        await engine.init(
          accessKey: 'test-access-key',
          modelPath: 'model.pv',
          keywordPath: 'keyword.ppn',
          sensitivity: 0.5,
        );

        await engine.dispose();
        await engine.dispose();

        expect(engine.processFrame(_magicFrame()), isFalse);
      },
    );

    test(
      'campos obrigatorios ausentes ativam fallback sem tentar FFI',
      () async {
        final engine = PicovoicePorcupineEngine(
          libraryLoader: () =>
              throw StateError('should not load native library'),
        );

        await engine.init(keywordPath: 'keyword.ppn', sensitivity: 0.5);

        expect(engine.processFrame(_magicFrame()), isTrue);

        await engine.dispose();
      },
    );
  });
}

Int16List _magicFrame() {
  final frame = Int16List(audioPipelineDefaultFrameSizeBytes ~/ 2);
  frame[0] = StubWakeWordEngine.magicSampleA;
  frame[1] = StubWakeWordEngine.magicSampleB;
  frame[2] = StubWakeWordEngine.magicSampleC;
  frame[3] = StubWakeWordEngine.magicSampleD;
  return frame;
}
