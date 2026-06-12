import 'dart:typed_data';

abstract class WakeWordEngine {
  Future<void> init({
    String? accessKey,
    String? modelPath,
    required String keywordPath,
    required double sensitivity,
  });

  bool processFrame(Int16List frame);
  Future<void> dispose();
}

/// Engine temporaria para validar o contrato de wake-word dentro do isolate.
///
/// Ela nao faz reconhecimento real. A deteccao simulada ocorre apenas quando
/// os quatro primeiros samples do frame batem com um padrao deterministico de
/// teste, respeitando cooldown para evitar cascatas de ativacao.
class StubWakeWordEngine implements WakeWordEngine {
  StubWakeWordEngine({this.cooldownFrames = 50});

  static const int magicSampleA = 4951;
  static const int magicSampleB = -9320;
  static const int magicSampleC = 4951;
  static const int magicSampleD = -9320;

  final int cooldownFrames;

  bool _initialized = false;
  int _framesSinceDetection = 1 << 30;
  double _sensitivity = 0.5;
  String _keywordPath = '';

  @override
  Future<void> init({
    String? accessKey,
    String? modelPath,
    required String keywordPath,
    required double sensitivity,
  }) async {
    _keywordPath = keywordPath;
    _sensitivity = sensitivity.clamp(0, 1).toDouble();
    _initialized = true;
    _framesSinceDetection = cooldownFrames;
  }

  @override
  bool processFrame(Int16List frame) {
    if (!_initialized || _keywordPath.isEmpty || _sensitivity <= 0) {
      return false;
    }
    if (frame.length < 4) {
      return false;
    }

    _framesSinceDetection += 1;
    if (_framesSinceDetection < cooldownFrames) {
      return false;
    }

    final detected =
        frame[0] == magicSampleA &&
        frame[1] == magicSampleB &&
        frame[2] == magicSampleC &&
        frame[3] == magicSampleD;
    if (!detected) {
      return false;
    }

    _framesSinceDetection = 0;
    return true;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _keywordPath = '';
    _sensitivity = 0.5;
    _framesSinceDetection = 1 << 30;
  }
}
