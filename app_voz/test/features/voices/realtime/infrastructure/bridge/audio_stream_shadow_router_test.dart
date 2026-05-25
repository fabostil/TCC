import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_isolate_bridge.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/bridge/audio_stream_shadow_router.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/persistence/pcm_wav_file_writer.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioStreamShadowRouter', () {
    late StreamController<Uint8List> chunks;
    late _FakeAudioIsolateBridge bridge;
    late VoiceRealtimeEventBus eventBus;
    late AudioStreamShadowRouter router;

    setUp(() {
      chunks = StreamController<Uint8List>.broadcast(sync: true);
      bridge = _FakeAudioIsolateBridge();
      eventBus = VoiceRealtimeEventBus();
      router = AudioStreamShadowRouter(bridge: bridge, eventBus: eventBus);
    });

    tearDown(() async {
      await router.dispose();
      await chunks.close();
    });

    test('repassa chunks para a bridge como AUDIO_CHUNK', () async {
      router.start(chunks.stream, correlationId: 'shadow-flow');

      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      chunks.add(first);
      chunks.add(second);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commands, [
        const _SentCommand(
          command: audioPipelineCommandStartCapture,
          correlationId: 'shadow-flow',
        ),
        _SentCommand(
          command: audioPipelineCommandAudioChunk,
          correlationId: 'shadow-flow',
          payload: first,
        ),
        _SentCommand(
          command: audioPipelineCommandAudioChunk,
          correlationId: 'shadow-flow',
          payload: second,
        ),
      ]);
    });

    test('descarta chunks quando a bridge nao esta disponivel', () async {
      bridge.available = false;
      bridge.startSucceeds = false;
      router.start(chunks.stream);

      chunks.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commands, isEmpty);
    });

    test('falha da bridge no meio do stream nao vaza excecao', () async {
      router.start(chunks.stream, correlationId: 'safe-shadow');

      chunks.add(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      bridge.throwOnSend = true;
      chunks.add(Uint8List.fromList([2]));
      bridge.throwOnSend = false;
      bridge.available = false;
      chunks.add(Uint8List.fromList([3]));
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commands, [
        const _SentCommand(
          command: audioPipelineCommandStartCapture,
          correlationId: 'safe-shadow',
        ),
        _SentCommand(
          command: audioPipelineCommandAudioChunk,
          correlationId: 'safe-shadow',
          payload: Uint8List.fromList([1]),
        ),
      ]);
    });

    test('dispose cancela assinatura do stream', () async {
      router.start(chunks.stream);
      bridge.commands.clear();
      await router.dispose();

      chunks.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(router.isActive, isFalse);
      expect(bridge.commands, const [
        _SentCommand(command: audioPipelineCommandStopCapture),
      ]);
    });

    test('suprime chunks durante TTS sem parar o stream principal', () async {
      router.start(chunks.stream, correlationId: 'echo-safe');
      bridge.commands.clear();

      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'test',
          previousState: 'ttsIdle',
          nextState: 'ttsSpeaking',
          reason: 'tts_test',
          correlationId: 'tts',
          metadata: {'text': 'Confirmado.'},
        ),
      );

      chunks.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(router.isActive, isTrue);
      expect(router.isSuppressingTtsEcho, isTrue);
      expect(bridge.commands, isEmpty);
    });

    test(
      'descarta frames antigos no shadow sem afetar arquivo wav principal',
      () async {
        await router.dispose();
        router = AudioStreamShadowRouter(
          bridge: bridge,
          eventBus: eventBus,
          maxQueuedFrames: 2,
        );
        final tempDir = await Directory.systemTemp.createTemp(
          'shadow_router_backpressure_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final writer = await PcmWavFileWriter.open('${tempDir.path}/take.wav');
        final observedChunks = <int>[];
        final eventSubscription = eventBus
            .on<AudioPipelineChunkReceivedEvent>()
            .listen((event) => observedChunks.add(event.chunk.first));

        router.start(chunks.stream, correlationId: 'overflow');
        bridge.commands.clear();

        for (var value = 1; value <= 5; value += 1) {
          final chunk = Uint8List.fromList([value]);
          writer.writeChunk(chunk);
          chunks.add(chunk);
        }
        await writer.flushAndClose();
        await Future<void>.delayed(Duration.zero);
        await eventSubscription.cancel();

        final audioChunkCommands = bridge.commands
            .where(
              (command) => command.command == audioPipelineCommandAudioChunk,
            )
            .toList();
        expect(router.droppedFrameCount, 3);
        expect(
          audioChunkCommands.map(
            (command) => (command.payload as Uint8List).first,
          ),
          [4, 5],
        );
        expect(observedChunks, [4, 5]);
        expect(await File('${tempDir.path}/take.wav').length(), 44 + 5);
      },
    );
  });
}

class _FakeAudioIsolateBridge implements AudioIsolateBridge {
  bool available = true;
  bool startSucceeds = true;
  bool throwOnSend = false;
  final List<_SentCommand> commands = [];

  @override
  bool get isAvailable => available;

  @override
  bool sendCommand(
    String command, {
    String? correlationId,
    String? causationId,
    Object? payload,
  }) {
    if (throwOnSend) {
      throw StateError('bridge failed');
    }
    commands.add(
      _SentCommand(
        command: command,
        correlationId: correlationId,
        causationId: causationId,
        payload: payload,
      ),
    );
    return true;
  }

  @override
  VoiceRealtimeEventBus get eventBus => VoiceRealtimeEventBus();

  @override
  Future<void> dispose({Duration timeout = const Duration(milliseconds: 500)}) {
    available = false;
    return Future<void>.value();
  }

  @override
  Future<bool> start({Duration timeout = const Duration(seconds: 2)}) {
    available = startSucceeds;
    return Future<bool>.value(startSucceeds);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SentCommand {
  const _SentCommand({
    required this.command,
    this.correlationId,
    this.causationId,
    this.payload,
  });

  final String command;
  final String? correlationId;
  final String? causationId;
  final Object? payload;

  @override
  bool operator ==(Object other) {
    return other is _SentCommand &&
        other.command == command &&
        other.correlationId == correlationId &&
        other.causationId == causationId &&
        _payloadEquals(other.payload, payload);
  }

  @override
  int get hashCode => Object.hash(
    command,
    correlationId,
    causationId,
    payload is Uint8List ? Object.hashAll(payload as Uint8List) : payload,
  );

  bool _payloadEquals(Object? left, Object? right) {
    if (left is Uint8List && right is Uint8List) {
      if (left.length != right.length) {
        return false;
      }
      for (var i = 0; i < left.length; i += 1) {
        if (left[i] != right[i]) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  @override
  String toString() {
    return '_SentCommand($command, $correlationId, $causationId, $payload)';
  }
}
