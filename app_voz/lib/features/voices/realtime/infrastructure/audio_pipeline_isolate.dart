import 'dart:isolate';
import 'dart:typed_data';

import 'vad/adaptive_silence_vad.dart';
import 'vad/audio_frame_accumulator.dart';
import 'wakeword/picovoice_porcupine_engine.dart';
import 'wakeword/wake_word_engine.dart';

const String audioPipelineCommandStartCapture = 'START_CAPTURE';
const String audioPipelineCommandStopCapture = 'STOP_CAPTURE';
const String audioPipelineCommandPing = 'PING';
const String audioPipelineCommandShutdown = 'SHUTDOWN';
const String audioPipelineCommandAudioChunk = 'AUDIO_CHUNK';

const String audioPipelineMessageReady = 'READY';
const String audioPipelineMessageCaptureStarted = 'CAPTURE_STARTED';
const String audioPipelineMessageCaptureStopped = 'CAPTURE_STOPPED';
const String audioPipelineMessagePong = 'PONG';
const String audioPipelineMessageShutdownComplete = 'SHUTDOWN_COMPLETE';
const String audioPipelineMessageError = 'ERROR';
const String audioPipelineMessageSilenceDetected = 'SILENCE_DETECTED';
const String audioPipelineMessageWakeWordDetected = 'WAKE_WORD_DETECTED';

const int audioPipelineDefaultFrameSizeBytes = 640;
const int audioPipelineDefaultConsecutiveSilentFrames = 5;

const String _picovoiceAccessKey = String.fromEnvironment(
  'PICOVOICE_ACCESS_KEY',
);
const String _picovoiceModelPath = String.fromEnvironment(
  'PICOVOICE_MODEL_PATH',
);
const String _picovoiceKeywordPath = String.fromEnvironment(
  'PICOVOICE_KEYWORD_PATH',
);
const String _picovoiceSensitivityValue = String.fromEnvironment(
  'PICOVOICE_SENSITIVITY',
  defaultValue: '0.5',
);

void startAudioPipeline(SendPort mainIsolatePort) {
  _startAudioPipelineAsync(mainIsolatePort);
}

Future<void> _startAudioPipelineAsync(SendPort mainIsolatePort) async {
  final commandPort = ReceivePort();
  final vad = AdaptiveSilenceVad();
  final accumulator = AudioFrameAccumulator(frameSizeBytes: vad.frameSizeBytes);
  final wakeWordEngine = _createWakeWordEngine();
  var capturing = false;
  var totalProcessedFrames = 0;

  await wakeWordEngine.init(
    accessKey: _picovoiceAccessKey.isEmpty ? null : _picovoiceAccessKey,
    modelPath: _picovoiceModelPath.isEmpty ? null : _picovoiceModelPath,
    keywordPath: _configuredKeywordPath,
    sensitivity: _configuredSensitivity,
  );

  mainIsolatePort.send({
    'type': audioPipelineMessageReady,
    'sendPort': commandPort.sendPort,
  });

  commandPort.listen((rawMessage) async {
    final message = _parsePipelineMessage(rawMessage);
    if (message == null) {
      mainIsolatePort.send({
        'type': audioPipelineMessageError,
        'error': 'invalid_message',
      });
      return;
    }

    final command = message['command'];
    final correlationId = message['correlationId'];

    switch (command) {
      case audioPipelineCommandStartCapture:
        capturing = true;
        totalProcessedFrames = 0;
        accumulator.clear();
        vad.reset();
        mainIsolatePort.send({
          'type': audioPipelineMessageCaptureStarted,
          'correlationId': correlationId,
          'capturing': capturing,
        });
      case audioPipelineCommandStopCapture:
        capturing = false;
        accumulator.clear();
        vad.reset();
        mainIsolatePort.send({
          'type': audioPipelineMessageCaptureStopped,
          'correlationId': correlationId,
          'capturing': capturing,
        });
      case audioPipelineCommandPing:
        mainIsolatePort.send({
          'type': audioPipelineMessagePong,
          'correlationId': correlationId,
          'capturing': capturing,
        });
      case audioPipelineCommandAudioChunk:
        if (!capturing) {
          return;
        }

        final payload = message['payload'];
        if (payload is! Uint8List) {
          mainIsolatePort.send({
            'type': audioPipelineMessageError,
            'correlationId': correlationId,
            'error': 'invalid_audio_payload',
          });
          return;
        }

        accumulator.addChunk(payload);
        var processedFrames = 0;
        while (accumulator.hasFrame) {
          final frame = accumulator.takeFrame();
          if (frame == null) {
            break;
          }
          processedFrames += 1;
          totalProcessedFrames += 1;
          final pcmFrame = _pcm16LittleEndianFrame(frame);
          if (wakeWordEngine.processFrame(pcmFrame)) {
            mainIsolatePort.send({
              'type': audioPipelineMessageWakeWordDetected,
              'correlationId': correlationId,
              'detectedAt': DateTime.now().toIso8601String(),
              'processedFrames': processedFrames,
              'totalProcessedFrames': totalProcessedFrames,
              'frameSizeBytes': vad.frameSizeBytes,
              'engine': _wakeWordEngineName,
            });
          }

          final result = vad.analyzeFrame(frame);

          if (result.consecutiveSilentFrames >=
              audioPipelineDefaultConsecutiveSilentFrames) {
            mainIsolatePort.send({
              'type': audioPipelineMessageSilenceDetected,
              'correlationId': correlationId,
              'silentFrames': result.consecutiveSilentFrames,
              'processedFrames': processedFrames,
              'rms': result.rms,
              'noiseFloor': result.noiseFloor,
              'adaptiveThreshold': result.threshold,
              'frameSizeBytes': vad.frameSizeBytes,
            });
            vad.resetConsecutiveSilence();
          }
        }
      case audioPipelineCommandShutdown:
        capturing = false;
        accumulator.clear();
        vad.reset();
        await wakeWordEngine.dispose();
        mainIsolatePort.send({
          'type': audioPipelineMessageShutdownComplete,
          'correlationId': correlationId,
          'capturing': capturing,
        });
        commandPort.close();
      default:
        mainIsolatePort.send({
          'type': audioPipelineMessageError,
          'correlationId': correlationId,
          'error': 'unknown_command',
          'command': command,
        });
    }
  });
}

WakeWordEngine _createWakeWordEngine() {
  if (_picovoiceAccessKey.isEmpty ||
      _picovoiceModelPath.isEmpty ||
      _picovoiceKeywordPath.isEmpty) {
    return StubWakeWordEngine();
  }
  return PicovoicePorcupineEngine();
}

String get _configuredKeywordPath {
  if (_picovoiceKeywordPath.isEmpty) {
    return 'stub://assistente-musical';
  }
  return _picovoiceKeywordPath;
}

String get _wakeWordEngineName {
  if (_picovoiceAccessKey.isEmpty ||
      _picovoiceModelPath.isEmpty ||
      _picovoiceKeywordPath.isEmpty) {
    return 'stub';
  }
  return 'picovoice_porcupine';
}

double get _configuredSensitivity {
  final parsed = double.tryParse(_picovoiceSensitivityValue);
  return (parsed ?? 0.5).clamp(0, 1).toDouble();
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

Map<String, Object?>? _parsePipelineMessage(Object? rawMessage) {
  if (rawMessage is String) {
    return {'command': rawMessage};
  }

  if (rawMessage is Map) {
    final command = rawMessage['command'];
    if (command is! String || command.isEmpty) {
      return null;
    }
    return {
      'command': command,
      'correlationId': rawMessage['correlationId'],
      'payload': rawMessage['payload'],
    };
  }

  return null;
}
