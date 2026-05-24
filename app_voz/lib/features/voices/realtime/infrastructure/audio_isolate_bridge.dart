import 'dart:async';
import 'dart:isolate';

import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'audio_pipeline_isolate.dart';

class AudioIsolateBridge {
  AudioIsolateBridge({VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  static final AudioIsolateBridge instance = AudioIsolateBridge();

  final VoiceRealtimeEventBus eventBus;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _pipelinePort;
  StreamSubscription? _isolateSubscription;
  StreamSubscription<StartVoiceCaptureRequestedEvent>? _startSubscription;
  StreamSubscription<StopVoiceCaptureRequestedEvent>? _stopSubscription;
  Completer<void>? _readyCompleter;
  Completer<void>? _shutdownCompleter;
  bool _disposed = false;
  bool _available = false;

  bool get isAvailable => _available && !_disposed && _pipelinePort != null;

  Future<bool> start({Duration timeout = const Duration(seconds: 2)}) async {
    if (_disposed) {
      return false;
    }
    if (isAvailable) {
      return true;
    }

    _readyCompleter = Completer<void>();
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _isolateSubscription = receivePort.listen(_handlePipelineMessage);

    try {
      _isolate = await Isolate.spawn(
        startAudioPipeline,
        receivePort.sendPort,
        debugName: 'audio_pipeline_isolate',
      );
      await _readyCompleter!.future.timeout(timeout);
      _startSubscription = eventBus
          .on<StartVoiceCaptureRequestedEvent>()
          .listen(_handleStartVoiceCaptureRequested);
      _stopSubscription = eventBus.on<StopVoiceCaptureRequestedEvent>().listen(
        _handleStopVoiceCaptureRequested,
      );
      return true;
    } catch (error) {
      eventBus.publish(
        AudioPipelineErrorEvent(
          source: 'audio_isolate_bridge',
          reason: 'startup_failed',
          metadata: {'error': error.toString()},
        ),
      );
      await _closeLocalResources(killIsolate: true);
      return false;
    }
  }

  bool sendCommand(
    String command, {
    String? correlationId,
    String? causationId,
    Object? payload,
  }) {
    final pipelinePort = _pipelinePort;
    if (_disposed || pipelinePort == null) {
      eventBus.publish(
        AudioPipelineErrorEvent(
          source: 'audio_isolate_bridge',
          reason: 'bridge_unavailable',
          correlationId: correlationId,
          causationId: causationId,
          metadata: {'command': command},
        ),
      );
      return false;
    }

    try {
      pipelinePort.send({
        'command': command,
        'correlationId': correlationId,
        'causationId': causationId,
        'payload': ?payload,
      });
      return true;
    } catch (error) {
      eventBus.publish(
        AudioPipelineErrorEvent(
          source: 'audio_isolate_bridge',
          reason: 'send_failed',
          correlationId: correlationId,
          causationId: causationId,
          metadata: {'command': command, 'error': error.toString()},
        ),
      );
      return false;
    }
  }

  void _handleStartVoiceCaptureRequested(
    StartVoiceCaptureRequestedEvent event,
  ) {
    sendCommand(
      audioPipelineCommandStartCapture,
      correlationId: event.correlationId,
      causationId: event.id,
    );
  }

  void _handleStopVoiceCaptureRequested(StopVoiceCaptureRequestedEvent event) {
    sendCommand(
      audioPipelineCommandStopCapture,
      correlationId: event.correlationId,
      causationId: event.id,
    );
  }

  void _handlePipelineMessage(Object? rawMessage) {
    final message = _parseBridgeMessage(rawMessage);
    if (message == null) {
      eventBus.publish(
        AudioPipelineErrorEvent(
          source: 'audio_isolate_bridge',
          reason: 'invalid_pipeline_message',
        ),
      );
      return;
    }

    final type = message['type'];
    final correlationId = _stringOrNull(message['correlationId']);
    final causationId = _stringOrNull(message['causationId']);

    if (type == audioPipelineMessageReady) {
      final sendPort = message['sendPort'];
      if (sendPort is SendPort) {
        _pipelinePort = sendPort;
        _available = true;
        _readyCompleter?.complete();
        eventBus.publish(
          AudioPipelineReadyEvent(
            source: 'audio_isolate_bridge',
            metadata: {'available': true},
          ),
        );
        return;
      }
      eventBus.publish(
        AudioPipelineErrorEvent(
          source: 'audio_isolate_bridge',
          reason: 'missing_send_port',
        ),
      );
      _readyCompleter?.completeError(StateError('missing_send_port'));
      return;
    }

    switch (type) {
      case audioPipelineMessageCaptureStarted:
        eventBus.publish(
          AudioPipelineCaptureStartedEvent(
            source: 'audio_isolate_bridge',
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
      case audioPipelineMessageCaptureStopped:
        eventBus.publish(
          AudioPipelineCaptureStoppedEvent(
            source: 'audio_isolate_bridge',
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
      case audioPipelineMessagePong:
        eventBus.publish(
          AudioPipelinePongEvent(
            source: 'audio_isolate_bridge',
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
      case audioPipelineMessageShutdownComplete:
        eventBus.publish(
          AudioPipelineShutdownCompleteEvent(
            source: 'audio_isolate_bridge',
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
        _shutdownCompleter?.complete();
      case audioPipelineMessageError:
        eventBus.publish(
          AudioPipelineErrorEvent(
            source: 'audio_isolate_bridge',
            reason: _stringOrNull(message['error']),
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
      case audioPipelineMessageSilenceDetected:
        eventBus.publish(
          SilenceDetectedEvent(
            source: 'audio_isolate_bridge',
            ownerId: null,
            reason: 'audio_pipeline_silence',
            correlationId: correlationId,
            causationId: causationId,
            silenceMs: (message['silentFrames'] as int? ?? 0) * 20,
            level: (message['rms'] as num?)?.toDouble() ?? 0,
            isIsolateEngine: true,
            metadata: _metadataFrom(message),
          ),
        );
      case audioPipelineMessageWakeWordDetected:
        final detectedAt =
            DateTime.tryParse(_stringOrNull(message['detectedAt']) ?? '') ??
            DateTime.now();
        eventBus.publish(
          VoiceWakeWordDetectedEvent(
            source: 'audio_isolate_bridge',
            reason: 'audio_pipeline_wake_word',
            correlationId:
                'wake_${detectedAt.microsecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}',
            causationId: causationId,
            detectedAt: detectedAt,
            metadata: {
              'pipelineCorrelationId': correlationId,
              ..._metadataFrom(message),
            },
          ),
        );
      default:
        eventBus.publish(
          AudioPipelineErrorEvent(
            source: 'audio_isolate_bridge',
            reason: 'unknown_pipeline_message',
            correlationId: correlationId,
            causationId: causationId,
            metadata: _metadataFrom(message),
          ),
        );
    }
  }

  Future<void> dispose({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    final pipelinePort = _pipelinePort;
    if (pipelinePort != null) {
      _shutdownCompleter = Completer<void>();
      pipelinePort.send({
        'command': audioPipelineCommandShutdown,
        'correlationId': 'audio_bridge_shutdown',
      });
      try {
        await _shutdownCompleter!.future.timeout(timeout);
      } catch (_) {
        eventBus.publish(
          AudioPipelineErrorEvent(
            source: 'audio_isolate_bridge',
            reason: 'shutdown_timeout',
            correlationId: 'audio_bridge_shutdown',
          ),
        );
      }
    }

    await _closeLocalResources(killIsolate: true);
  }

  Future<void> _closeLocalResources({required bool killIsolate}) async {
    await _startSubscription?.cancel();
    _startSubscription = null;
    await _stopSubscription?.cancel();
    _stopSubscription = null;
    await _isolateSubscription?.cancel();
    _isolateSubscription = null;
    _receivePort?.close();
    _receivePort = null;
    _pipelinePort = null;
    _available = false;
    if (killIsolate) {
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      _isolate = null;
    }
  }

  Map<String, Object?>? _parseBridgeMessage(Object? rawMessage) {
    if (rawMessage is! Map) {
      return null;
    }
    final type = rawMessage['type'];
    if (type is! String || type.isEmpty) {
      return null;
    }
    return {
      for (final entry in rawMessage.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  Map<String, Object?> _metadataFrom(Map<String, Object?> message) {
    return Map.unmodifiable({
      for (final entry in message.entries)
        if (entry.key != 'type' &&
            entry.key != 'correlationId' &&
            entry.key != 'causationId' &&
            entry.key != 'sendPort')
          entry.key: entry.value,
    });
  }

  String? _stringOrNull(Object? value) => value is String ? value : null;
}
