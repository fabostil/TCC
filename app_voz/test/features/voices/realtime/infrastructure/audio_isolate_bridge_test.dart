import 'dart:isolate';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_isolate_bridge.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioIsolateBridge', () {
    late VoiceRealtimeEventBus bus;
    late AudioIsolateBridge bridge;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      bridge = AudioIsolateBridge(eventBus: bus);
    });

    tearDown(() async {
      await bridge.dispose();
    });

    test('realiza handshake de inicializacao entre portas', () async {
      final started = await bridge.start();

      expect(started, isTrue);
      expect(bridge.isAvailable, isTrue);
      expect(bus.timeline.whereType<AudioPipelineReadyEvent>(), hasLength(1));
    });

    test('envia comando e publica resposta tipada do isolate', () async {
      final started = await bridge.start();
      expect(started, isTrue);

      final sent = bridge.sendCommand(
        audioPipelineCommandPing,
        correlationId: 'ping-flow',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sent, isTrue);
      final pong = bus.timeline.whereType<AudioPipelinePongEvent>().single;
      expect(pong.correlationId, 'ping-flow');
      expect(pong.metadata['capturing'], isFalse);
    });

    test(
      'traduz StopVoiceCaptureRequested em STOP_CAPTURE no pipeline',
      () async {
        final started = await bridge.start();
        expect(started, isTrue);

        bridge.sendCommand(
          audioPipelineCommandStartCapture,
          correlationId: 'capture-flow',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bus.publish(
          StopVoiceCaptureRequestedEvent(
            source: 'test',
            ownerId: 'editor',
            correlationId: 'capture-flow',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          bus.timeline.whereType<AudioPipelineCaptureStartedEvent>(),
          hasLength(1),
        );
        final stopped = bus.timeline
            .whereType<AudioPipelineCaptureStoppedEvent>()
            .single;
        expect(stopped.correlationId, 'capture-flow');
        expect(stopped.metadata['capturing'], isFalse);
      },
    );

    test(
      'dispose envia shutdown e encerra bridge sem novas respostas',
      () async {
        final started = await bridge.start();
        expect(started, isTrue);

        await bridge.dispose();
        final sentAfterDispose = bridge.sendCommand(
          audioPipelineCommandPing,
          correlationId: 'after-dispose',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bridge.isAvailable, isFalse);
        expect(sentAfterDispose, isFalse);
        expect(
          bus.timeline.whereType<AudioPipelineShutdownCompleteEvent>(),
          hasLength(1),
        );
        expect(
          bus.timeline.whereType<AudioPipelinePongEvent>().where(
            (event) => event.correlationId == 'after-dispose',
          ),
          isEmpty,
        );
      },
    );

    test(
      'processa AUDIO_CHUNK silencioso e publica SilenceDetectedEvent',
      () async {
        final started = await bridge.start();
        expect(started, isTrue);

        bridge.sendCommand(
          audioPipelineCommandStartCapture,
          correlationId: 'vad-flow',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final silenceBytes = Uint8List.fromList(
          List<int>.filled(audioPipelineDefaultFrameSizeBytes * 5, 128),
        );
        final sent = bridge.sendCommand(
          audioPipelineCommandAudioChunk,
          correlationId: 'vad-flow',
          payload: silenceBytes,
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(sent, isTrue);
        final silence = bus.timeline.whereType<SilenceDetectedEvent>().single;
        expect(silence.correlationId, 'vad-flow');
        expect(silence.reason, 'audio_pipeline_silence');
        expect(silence.metadata['level'], 0);
        expect(silence.metadata['silenceMs'], 100);
        expect(silence.message, 'Silencio detectado.');
      },
    );

    test('ignora AUDIO_CHUNK quando captura nao esta ativa', () async {
      final started = await bridge.start();
      expect(started, isTrue);

      bridge.sendCommand(
        audioPipelineCommandAudioChunk,
        correlationId: 'ignored-vad-flow',
        payload: Uint8List.fromList(
          List<int>.filled(audioPipelineDefaultFrameSizeBytes * 5, 128),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(bus.timeline.whereType<SilenceDetectedEvent>(), isEmpty);
      expect(bus.timeline.whereType<AudioPipelineErrorEvent>(), isEmpty);
    });
  });

  group('startAudioPipeline', () {
    test('responde erro deterministico para mensagem invalida', () async {
      final mainPort = ReceivePort();
      final messages = <Object?>[];
      final subscription = mainPort.listen(messages.add);
      final isolate = await Isolate.spawn(
        startAudioPipeline,
        mainPort.sendPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final ready = messages.whereType<Map>().firstWhere(
        (message) => message['type'] == audioPipelineMessageReady,
      );
      final pipelinePort = ready['sendPort'] as SendPort;

      pipelinePort.send({'command': audioPipelineCommandPing});
      pipelinePort.send({'invalid': true});
      pipelinePort.send({
        'command': audioPipelineCommandShutdown,
        'correlationId': 'shutdown',
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        messages.whereType<Map>().where(
          (event) => event['type'] == audioPipelineMessageError,
        ),
        hasLength(1),
      );

      await subscription.cancel();
      mainPort.close();
      isolate.kill(priority: Isolate.immediate);
    });
  });
}
