import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/runtime/runtime_engine.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_registry.dart';
import 'package:app_voz/features/voices/realtime/stt/streaming_speech_recognizer.dart';
import 'package:app_voz/features/voices/realtime/stt/unsupported_speech_recognizer.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingSpeechRecognizer runtime facade', () {
    test(
      'stream-first ligado inicializa, alimenta e para recognizer',
      () async {
        final bus = VoiceRealtimeEventBus();
        final recognizer = _FakeStreamingSpeechRecognizer();
        final engine = VoiceRuntimeEngine(
          eventBus: bus,
          registry: VoiceRuntimeRegistry(eventBus: bus),
          useStreamFirstAudio: true,
          streamingSpeechRecognizer: recognizer,
        )..start();

        bus.publish(
          AudioPipelineCaptureStartedEvent(
            source: 'test',
            correlationId: 'stream-flow',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bus.publish(
          AudioPipelineChunkReceivedEvent(
            source: 'test',
            correlationId: 'stream-flow',
            chunk: Uint8List.fromList([1, 2, 3]),
          ),
        );
        bus.publish(
          AudioPipelineChunkReceivedEvent(
            source: 'test',
            correlationId: 'other-flow',
            chunk: Uint8List.fromList([9, 9, 9]),
          ),
        );
        bus.publish(
          AudioPipelineCaptureStoppedEvent(
            source: 'test',
            correlationId: 'stream-flow',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(recognizer.initializeCalls, 1);
        expect(recognizer.startedCorrelations, ['stream-flow']);
        expect(recognizer.chunks.map((chunk) => chunk.toList()), [
          [1, 2, 3],
        ]);
        expect(recognizer.stopCalls, 1);

        await engine.dispose();
      },
    );

    test('stream-first desligado nao aciona recognizer streaming', () async {
      final bus = VoiceRealtimeEventBus();
      final recognizer = _FakeStreamingSpeechRecognizer();
      final engine = VoiceRuntimeEngine(
        eventBus: bus,
        registry: VoiceRuntimeRegistry(eventBus: bus),
        useStreamFirstAudio: false,
        streamingSpeechRecognizer: recognizer,
      )..start();

      bus.publish(
        AudioPipelineCaptureStartedEvent(
          source: 'test',
          correlationId: 'legacy-flow',
        ),
      );
      bus.publish(
        AudioPipelineChunkReceivedEvent(
          source: 'test',
          correlationId: 'legacy-flow',
          chunk: Uint8List.fromList([1, 2, 3]),
        ),
      );
      bus.publish(
        AudioPipelineCaptureStoppedEvent(
          source: 'test',
          correlationId: 'legacy-flow',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(recognizer.initializeCalls, 0);
      expect(recognizer.startedCorrelations, isEmpty);
      expect(recognizer.chunks, isEmpty);
      expect(recognizer.stopCalls, 0);

      await engine.dispose();
    });

    test(
      'UnsupportedSpeechRecognizer publica telemetria sem abrir STT',
      () async {
        final bus = VoiceRealtimeEventBus();
        final recognizer = UnsupportedSpeechRecognizer(eventBus: bus);

        await recognizer.initializeRecognizer();
        await recognizer.startRecognition('unsupported-flow');
        recognizer.feedAudioChunk(Uint8List.fromList([1, 2, 3, 4]));
        await recognizer.stopRecognition();

        final events = bus.timeline.whereType<VoiceSystemDegradedEvent>();
        expect(events.map((event) => event.reason), [
          'streaming_stt_unavailable',
          'streaming_stt_placeholder_active',
          'streaming_stt_placeholder_stopped',
        ]);
        final stopped = events.last;
        expect(stopped.correlationId, 'unsupported-flow');
        expect(stopped.metadata['chunksReceived'], 1);
        expect(stopped.metadata['bytesReceived'], 4);
      },
    );
  });
}

class _FakeStreamingSpeechRecognizer implements StreamingSpeechRecognizer {
  int initializeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<String> startedCorrelations = [];
  final List<Uint8List> chunks = [];

  @override
  Future<void> initializeRecognizer() async {
    initializeCalls += 1;
  }

  @override
  Future<void> startRecognition(String correlationId) async {
    startedCorrelations.add(correlationId);
  }

  @override
  void feedAudioChunk(Uint8List chunk) {
    chunks.add(chunk);
  }

  @override
  Future<void> stopRecognition() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
