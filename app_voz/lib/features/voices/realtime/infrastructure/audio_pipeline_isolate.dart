import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'vad/audio_frame_accumulator.dart';

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

const int audioPipelineDefaultFrameSizeBytes = 320;
const double audioPipelineDefaultSilenceRmsThreshold = 2.0;
const int audioPipelineDefaultConsecutiveSilentFrames = 5;

void startAudioPipeline(SendPort mainIsolatePort) {
  final commandPort = ReceivePort();
  final accumulator = AudioFrameAccumulator(
    frameSizeBytes: audioPipelineDefaultFrameSizeBytes,
  );
  var capturing = false;
  var consecutiveSilentFrames = 0;

  mainIsolatePort.send({
    'type': audioPipelineMessageReady,
    'sendPort': commandPort.sendPort,
  });

  commandPort.listen((rawMessage) {
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
        consecutiveSilentFrames = 0;
        accumulator.clear();
        mainIsolatePort.send({
          'type': audioPipelineMessageCaptureStarted,
          'correlationId': correlationId,
          'capturing': capturing,
        });
      case audioPipelineCommandStopCapture:
        capturing = false;
        consecutiveSilentFrames = 0;
        accumulator.clear();
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
        var lastRms = 0.0;
        while (accumulator.hasFrame) {
          final frame = accumulator.takeFrame();
          if (frame == null) {
            break;
          }
          processedFrames += 1;
          lastRms = _calculateRms(frame);
          if (lastRms < audioPipelineDefaultSilenceRmsThreshold) {
            consecutiveSilentFrames += 1;
          } else {
            consecutiveSilentFrames = 0;
          }

          if (consecutiveSilentFrames >=
              audioPipelineDefaultConsecutiveSilentFrames) {
            mainIsolatePort.send({
              'type': audioPipelineMessageSilenceDetected,
              'correlationId': correlationId,
              'silentFrames': consecutiveSilentFrames,
              'processedFrames': processedFrames,
              'rms': lastRms,
              'frameSizeBytes': audioPipelineDefaultFrameSizeBytes,
            });
            consecutiveSilentFrames = 0;
          }
        }
      case audioPipelineCommandShutdown:
        capturing = false;
        accumulator.clear();
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

double _calculateRms(Uint8List frame) {
  if (frame.isEmpty) {
    return 0;
  }

  var sumSquares = 0;
  for (final byte in frame) {
    final centered = byte - 128;
    sumSquares += centered * centered;
  }
  return math.sqrt(sumSquares / frame.length);
}
