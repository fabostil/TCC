import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../audio_isolate_bridge.dart';
import '../audio_pipeline_isolate.dart';

class AudioStreamShadowRouter {
  AudioStreamShadowRouter({
    AudioIsolateBridge? bridge,
    VoiceRealtimeEventBus? eventBus,
    int maxQueuedFrames = 50,
  }) : _bridge = bridge ?? AudioIsolateBridge.instance,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _maxQueuedFrames = maxQueuedFrames {
    if (maxQueuedFrames <= 0) {
      throw ArgumentError.value(
        maxQueuedFrames,
        'maxQueuedFrames',
        'deve ser positivo',
      );
    }
    _ttsStateSubscription = _eventBus.on<VoiceStateChangedEvent>().listen(
      _handleVoiceStateChanged,
    );
  }

  final AudioIsolateBridge _bridge;
  final VoiceRealtimeEventBus _eventBus;
  final int _maxQueuedFrames;
  final Queue<_PendingAudioChunk> _pendingChunks = Queue<_PendingAudioChunk>();

  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<VoiceStateChangedEvent>? _ttsStateSubscription;
  DateTime? _suppressAudioUntil;
  String? _activeCorrelationId;
  bool _disposed = false;
  bool _captureActive = false;
  bool _drainScheduled = false;
  int _droppedFrames = 0;
  int _droppedFramesSinceLastTelemetry = 0;

  bool get isActive => _subscription != null;
  bool get isSuppressingTtsEcho => _isSuppressingTtsEcho;
  int get queuedFrameCount => _pendingChunks.length;
  int get droppedFrameCount => _droppedFrames;

  void start(Stream<Uint8List> audioChunks, {String? correlationId}) {
    if (_disposed) {
      return;
    }

    if (isActive || _captureActive) {
      unawaited(stop());
    }
    _activeCorrelationId = correlationId;
    unawaited(_startPipelineCapture(correlationId: correlationId));
    _subscription = audioChunks.listen(
      (chunk) => _forward(chunk, correlationId: correlationId),
      onError: (_, _) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _pendingChunks.clear();
    await _stopPipelineCapture(correlationId: _activeCorrelationId);
    _activeCorrelationId = null;
  }

  void _forward(Uint8List chunk, {String? correlationId}) {
    if (_isSuppressingTtsEcho) {
      return;
    }

    if (_disposed || !_bridge.isAvailable || chunk.isEmpty) {
      return;
    }

    while (_pendingChunks.length >= _maxQueuedFrames) {
      _pendingChunks.removeFirst();
      _droppedFrames += 1;
      _droppedFramesSinceLastTelemetry += 1;
    }

    _pendingChunks.addLast(
      _PendingAudioChunk(chunk: chunk, correlationId: correlationId),
    );
    _scheduleDrain();
  }

  void _scheduleDrain() {
    if (_drainScheduled) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(_drainPendingChunks);
  }

  void _drainPendingChunks() {
    _drainScheduled = false;
    if (_disposed || !_bridge.isAvailable) {
      return;
    }

    while (_pendingChunks.isNotEmpty && !_disposed && _bridge.isAvailable) {
      final pending = _pendingChunks.removeFirst();
      final droppedSinceLastTelemetry = _droppedFramesSinceLastTelemetry;
      _droppedFramesSinceLastTelemetry = 0;

      if (droppedSinceLastTelemetry > 0) {
        // Aggregate dropped-frame telemetry on the next surviving chunk.
        debugPrint(
          'AudioStreamShadowRouter: frames descartados no shadow='
          '$droppedSinceLastTelemetry total=$_droppedFrames',
        );
      }

      _eventBus.publish(
        AudioPipelineChunkReceivedEvent(
          source: 'audio_stream_shadow_router',
          chunk: pending.chunk,
          correlationId: pending.correlationId,
          metadata: droppedSinceLastTelemetry > 0
              ? {
                  'droppedFrames': droppedSinceLastTelemetry,
                  'totalDroppedFrames': _droppedFrames,
                  'maxQueuedFrames': _maxQueuedFrames,
                }
              : const {},
        ),
      );

      try {
        _bridge.sendCommand(
          audioPipelineCommandAudioChunk,
          correlationId: pending.correlationId,
          payload: pending.chunk,
        );
      } catch (_) {
        // Shadow mode never propagates bridge failures to the recording pipeline.
      }
    }
  }

  Future<void> _startPipelineCapture({String? correlationId}) async {
    if (_captureActive) {
      return;
    }

    final available = _bridge.isAvailable || await _bridge.start();
    if (!available || _disposed) {
      return;
    }

    _captureActive = _bridge.sendCommand(
      audioPipelineCommandStartCapture,
      correlationId: correlationId,
    );
  }

  Future<void> _stopPipelineCapture({String? correlationId}) async {
    if (!_captureActive) {
      return;
    }
    _captureActive = false;
    if (!_bridge.isAvailable) {
      return;
    }

    _bridge.sendCommand(
      audioPipelineCommandStopCapture,
      correlationId: correlationId,
    );
  }

  void _handleVoiceStateChanged(VoiceStateChangedEvent event) {
    final nextState = event.metadata['nextState'];
    final normalizedNextState = nextState is String
        ? nextState.toLowerCase()
        : '';
    if (!normalizedNextState.contains('ttsspeaking')) {
      if (normalizedNextState.contains('ttsidle')) {
        _suppressAudioUntil = null;
      }
      return;
    }

    final text = event.metadata['text'];
    final textLength = text is String ? text.length : 80;
    final estimatedSpeechMs = (textLength * 65).clamp(1200, 6000).toInt();
    _suppressAudioUntil = DateTime.now().add(
      Duration(milliseconds: estimatedSpeechMs),
    );
  }

  bool get _isSuppressingTtsEcho {
    final suppressUntil = _suppressAudioUntil;
    if (suppressUntil == null) {
      return false;
    }
    if (DateTime.now().isBefore(suppressUntil)) {
      return true;
    }
    _suppressAudioUntil = null;
    return false;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    await _ttsStateSubscription?.cancel();
    _ttsStateSubscription = null;
  }
}

class _PendingAudioChunk {
  const _PendingAudioChunk({required this.chunk, required this.correlationId});

  final Uint8List chunk;
  final String? correlationId;
}
