import 'dart:math' as math;
import 'dart:typed_data';

class AdaptiveSilenceResult {
  const AdaptiveSilenceResult({
    required this.rms,
    required this.noiseFloor,
    required this.threshold,
    required this.isSilent,
    required this.consecutiveSilentFrames,
  });

  final double rms;
  final double noiseFloor;
  final double threshold;
  final bool isSilent;
  final int consecutiveSilentFrames;
}

class AdaptiveSilenceVad {
  AdaptiveSilenceVad({
    this.sampleRate = 16000,
    this.numChannels = 1,
    this.frameDurationMs = 20,
    this.noiseWindowFrames = 150,
    this.noiseMarginRms = 120,
    this.minimumSilenceThresholdRms = 150,
  }) : assert(sampleRate > 0),
       assert(numChannels > 0),
       assert(frameDurationMs > 0),
       assert(noiseWindowFrames > 0),
       frameSizeBytes = sampleRate * frameDurationMs ~/ 1000 * numChannels * 2,
       _recentRms = List<double>.filled(noiseWindowFrames, 0);

  final int sampleRate;
  final int numChannels;
  final int frameDurationMs;
  final int noiseWindowFrames;
  final double noiseMarginRms;
  final double minimumSilenceThresholdRms;
  final int frameSizeBytes;

  final List<double> _recentRms;
  int _recentCount = 0;
  int _recentIndex = 0;
  int _consecutiveSilentFrames = 0;

  int get consecutiveSilentFrames => _consecutiveSilentFrames;

  AdaptiveSilenceResult analyzeFrame(Uint8List frame) {
    final rms = calculatePcm16Rms(frame);
    _recordRms(rms);
    final noiseFloor = _noiseFloor();
    final threshold = math.max(
      minimumSilenceThresholdRms,
      noiseFloor + noiseMarginRms,
    );
    final isSilent = rms <= threshold;

    if (isSilent) {
      _consecutiveSilentFrames += 1;
    } else {
      _consecutiveSilentFrames = 0;
    }

    return AdaptiveSilenceResult(
      rms: rms,
      noiseFloor: noiseFloor,
      threshold: threshold,
      isSilent: isSilent,
      consecutiveSilentFrames: _consecutiveSilentFrames,
    );
  }

  void reset() {
    _recentCount = 0;
    _recentIndex = 0;
    _consecutiveSilentFrames = 0;
  }

  void resetConsecutiveSilence() {
    _consecutiveSilentFrames = 0;
  }

  void _recordRms(double rms) {
    _recentRms[_recentIndex] = rms;
    _recentIndex = (_recentIndex + 1) % noiseWindowFrames;
    if (_recentCount < noiseWindowFrames) {
      _recentCount += 1;
    }
  }

  double _noiseFloor() {
    if (_recentCount == 0) {
      return 0;
    }

    var minimum = _recentRms[0];
    for (var i = 1; i < _recentCount; i += 1) {
      final value = _recentRms[i];
      if (value < minimum) {
        minimum = value;
      }
    }
    return minimum;
  }
}

double calculatePcm16Rms(Uint8List frame) {
  if (frame.length < 2) {
    return 0;
  }

  final byteData = ByteData.sublistView(frame);
  final sampleCount = frame.length ~/ 2;
  var sumSquares = 0.0;

  for (var i = 0; i < sampleCount; i += 1) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    sumSquares += sample * sample;
  }

  return math.sqrt(sumSquares / sampleCount);
}
