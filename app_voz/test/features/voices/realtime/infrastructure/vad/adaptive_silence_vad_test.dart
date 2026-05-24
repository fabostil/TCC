import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/vad/adaptive_silence_vad.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveSilenceVad', () {
    test('calcula RMS real a partir de PCM16 little-endian', () {
      final frame = _pcm16Frame([1000, -1000, 1000, -1000]);

      expect(calculatePcm16Rms(frame), closeTo(1000, 0.001));
    });

    test('adapta limiar usando piso de ruido recente', () {
      final vad = AdaptiveSilenceVad(
        noiseWindowFrames: 4,
        noiseMarginRms: 120,
        minimumSilenceThresholdRms: 150,
      );

      final ambient = vad.analyzeFrame(_constantPcm16Frame(300));
      expect(ambient.noiseFloor, closeTo(300, 0.001));
      expect(ambient.threshold, closeTo(420, 0.001));
      expect(ambient.isSilent, isTrue);

      final speech = vad.analyzeFrame(_constantPcm16Frame(2200));
      expect(speech.noiseFloor, closeTo(300, 0.001));
      expect(speech.threshold, closeTo(420, 0.001));
      expect(speech.isSilent, isFalse);
      expect(speech.consecutiveSilentFrames, 0);

      final nextAmbient = vad.analyzeFrame(_constantPcm16Frame(320));
      expect(nextAmbient.isSilent, isTrue);
      expect(nextAmbient.consecutiveSilentFrames, 1);
    });

    test('usa frame de 20ms para PCM16 16kHz mono', () {
      final vad = AdaptiveSilenceVad();

      expect(vad.frameSizeBytes, 640);
    });
  });
}

Uint8List _constantPcm16Frame(int amplitude) {
  return _pcm16Frame(List<int>.filled(320, amplitude));
}

Uint8List _pcm16Frame(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i += 1) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}
