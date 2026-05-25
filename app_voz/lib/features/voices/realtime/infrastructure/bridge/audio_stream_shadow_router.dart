import 'dart:async';
import 'dart:typed_data';

import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../audio_isolate_bridge.dart';
import '../audio_pipeline_isolate.dart';

class AudioStreamShadowRouter {
  AudioStreamShadowRouter({
    AudioIsolateBridge? bridge,
    VoiceRealtimeEventBus? eventBus,
  }) : _bridge = bridge ?? AudioIsolateBridge.instance,
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance {
    _ttsStateSubscription = _eventBus.on<VoiceStateChangedEvent>().listen(
      _handleVoiceStateChanged,
    );
  }

  final AudioIsolateBridge _bridge;
  final VoiceRealtimeEventBus _eventBus;

  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<VoiceStateChangedEvent>? _ttsStateSubscription;
  DateTime? _suppressAudioUntil;
  String? _activeCorrelationId;
  bool _disposed = false;
  bool _captureActive = false;

  bool get isActive => _subscription != null;
  bool get isSuppressingTtsEcho => _isSuppressingTtsEcho;

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
    await _stopPipelineCapture(correlationId: _activeCorrelationId);
    _activeCorrelationId = null;
  }

  void _forward(Uint8List chunk, {String? correlationId}) {
    if (_isSuppressingTtsEcho) {
      return;
    }

    _eventBus.publish(
      AudioPipelineChunkReceivedEvent(
        source: 'audio_stream_shadow_router',
        chunk: chunk,
        correlationId: correlationId,
      ),
    );

    if (_disposed || !_bridge.isAvailable || chunk.isEmpty) {
      return;
    }

    try {
      _bridge.sendCommand(
        audioPipelineCommandAudioChunk,
        correlationId: correlationId,
        payload: chunk,
      );
    } catch (_) {
      // Shadow mode never propagates bridge failures to the recording pipeline.
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
