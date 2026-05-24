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
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final AudioIsolateBridge _bridge;
  final VoiceRealtimeEventBus _eventBus;

  StreamSubscription<Uint8List>? _subscription;
  bool _disposed = false;

  bool get isActive => _subscription != null;

  void start(Stream<Uint8List> audioChunks, {String? correlationId}) {
    if (_disposed) {
      return;
    }

    unawaited(stop());
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
  }

  void _forward(Uint8List chunk, {String? correlationId}) {
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

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
  }
}
