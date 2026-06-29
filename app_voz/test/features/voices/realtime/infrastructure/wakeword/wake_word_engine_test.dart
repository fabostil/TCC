import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_isolate_bridge.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/wakeword/wake_word_engine.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StubWakeWordEngine', () {
    test('detecta apenas padrao deterministico e respeita cooldown', () async {
      final engine = StubWakeWordEngine(cooldownFrames: 3);
      await engine.init(keywordPath: 'stub://keyword', sensitivity: 0.5);

      expect(engine.processFrame(_magicFrame()), isTrue);
      expect(engine.processFrame(_magicFrame()), isFalse);
      expect(engine.processFrame(_normalFrame()), isFalse);
      expect(engine.processFrame(_normalFrame()), isFalse);
      expect(engine.processFrame(_magicFrame()), isTrue);

      await engine.dispose();
      expect(engine.processFrame(_magicFrame()), isFalse);
    });
  });

  group('wake-word no AudioPipelineIsolate', () {
    late VoiceRealtimeEventBus bus;
    late AudioIsolateBridge bridge;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      bridge = AudioIsolateBridge(eventBus: bus);
    });

    tearDown(() async {
      await bridge.dispose();
    });

    test(
      'publica VoiceWakeWordDetectedEvent sem travar o loop de audio',
      () async {
        final started = await bridge.start();
        expect(started, isTrue);

        bridge.sendCommand(
          audioPipelineCommandStartCapture,
          correlationId: 'capture-flow',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final sent = bridge.sendCommand(
          audioPipelineCommandAudioChunk,
          correlationId: 'capture-flow',
          payload: _magicFrameBytes(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(sent, isTrue);
        final wake = bus.timeline
            .whereType<VoiceWakeWordDetectedEvent>()
            .single;
        expect(wake.reason, 'audio_pipeline_wake_word');
        expect(wake.correlationId, startsWith('wake_'));
        expect(wake.metadata['pipelineCorrelationId'], 'capture-flow');
        expect(wake.metadata['engine'], 'stub');
        expect(
          wake.metadata['frameSizeBytes'],
          audioPipelineDefaultFrameSizeBytes,
        );

        final pongSent = bridge.sendCommand(
          audioPipelineCommandPing,
          correlationId: 'after-wake',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(pongSent, isTrue);
        expect(
          bus.timeline.whereType<AudioPipelinePongEvent>().where(
            (event) => event.correlationId == 'after-wake',
          ),
          hasLength(1),
        );
      },
    );

    test('cooldown evita ativacoes repetidas em frames consecutivos', () async {
      final started = await bridge.start();
      expect(started, isTrue);

      bridge.sendCommand(
        audioPipelineCommandStartCapture,
        correlationId: 'cooldown-flow',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bridge.sendCommand(
        audioPipelineCommandAudioChunk,
        correlationId: 'cooldown-flow',
        payload: _twoMagicFramesBytes(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        bus.timeline.whereType<VoiceWakeWordDetectedEvent>(),
        hasLength(1),
      );
    });
  });
}

Int16List _magicFrame() {
  final frame = Int16List(audioPipelineDefaultFrameSizeBytes ~/ 2);
  frame[0] = StubWakeWordEngine.magicSampleA;
  frame[1] = StubWakeWordEngine.magicSampleB;
  frame[2] = StubWakeWordEngine.magicSampleC;
  frame[3] = StubWakeWordEngine.magicSampleD;
  return frame;
}

Int16List _normalFrame() {
  return Int16List(audioPipelineDefaultFrameSizeBytes ~/ 2);
}

Uint8List _magicFrameBytes() {
  return _pcm16FrameBytes(_magicFrame());
}

Uint8List _twoMagicFramesBytes() {
  final first = _magicFrameBytes();
  final second = _magicFrameBytes();
  final combined = Uint8List(first.length + second.length);
  combined.setRange(0, first.length, first);
  combined.setRange(first.length, combined.length, second);
  return combined;
}

Uint8List _pcm16FrameBytes(Int16List samples) {
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i += 1) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}
