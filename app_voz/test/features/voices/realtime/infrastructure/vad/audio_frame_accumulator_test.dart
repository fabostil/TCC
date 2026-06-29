import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/vad/audio_frame_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioFrameAccumulator', () {
    test('fatia bytes em frames fixos sem perda', () {
      final accumulator = AudioFrameAccumulator(frameSizeBytes: 4);

      accumulator.addChunk(Uint8List.fromList([1, 2]));
      expect(accumulator.takeFrame(), isNull);
      expect(accumulator.pendingBytes, 2);

      accumulator.addChunk(Uint8List.fromList([3, 4, 5, 6, 7]));

      expect(accumulator.takeFrame(), [1, 2, 3, 4]);
      expect(accumulator.pendingBytes, 3);
      expect(accumulator.takeFrame(), isNull);

      accumulator.addChunk(Uint8List.fromList([8]));
      expect(accumulator.takeFrame(), [5, 6, 7, 8]);
      expect(accumulator.pendingBytes, 0);
    });

    test('extrai multiplos frames de um unico chunk', () {
      final accumulator = AudioFrameAccumulator(frameSizeBytes: 3);

      accumulator.addChunk(Uint8List.fromList([10, 11, 12, 13, 14, 15, 16]));

      expect(accumulator.takeFrame(), [10, 11, 12]);
      expect(accumulator.takeFrame(), [13, 14, 15]);
      expect(accumulator.takeFrame(), isNull);
      expect(accumulator.pendingBytes, 1);

      accumulator.addChunk(Uint8List.fromList([17, 18]));
      expect(accumulator.takeFrame(), [16, 17, 18]);
    });

    test('clear descarta bytes pendentes e reinicia alinhamento', () {
      final accumulator = AudioFrameAccumulator(frameSizeBytes: 4);

      accumulator.addChunk(Uint8List.fromList([1, 2, 3]));
      accumulator.clear();
      accumulator.addChunk(Uint8List.fromList([4, 5, 6, 7]));

      expect(accumulator.pendingBytes, 4);
      expect(accumulator.takeFrame(), [4, 5, 6, 7]);
    });
  });
}
