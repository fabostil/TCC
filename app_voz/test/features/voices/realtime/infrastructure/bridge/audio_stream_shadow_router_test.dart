import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/audio_isolate_bridge.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/bridge/audio_stream_shadow_router.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioStreamShadowRouter', () {
    late StreamController<Uint8List> chunks;
    late _FakeAudioIsolateBridge bridge;
    late AudioStreamShadowRouter router;

    setUp(() {
      chunks = StreamController<Uint8List>.broadcast(sync: true);
      bridge = _FakeAudioIsolateBridge();
      router = AudioStreamShadowRouter(bridge: bridge);
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
      router.start(chunks.stream);

      chunks.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commands, isEmpty);
    });

    test('falha da bridge no meio do stream nao vaza excecao', () async {
      router.start(chunks.stream, correlationId: 'safe-shadow');

      chunks.add(Uint8List.fromList([1]));
      bridge.throwOnSend = true;
      chunks.add(Uint8List.fromList([2]));
      bridge.throwOnSend = false;
      bridge.available = false;
      chunks.add(Uint8List.fromList([3]));
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commands, [
        _SentCommand(
          command: audioPipelineCommandAudioChunk,
          correlationId: 'safe-shadow',
          payload: Uint8List.fromList([1]),
        ),
      ]);
    });

    test('dispose cancela assinatura do stream', () async {
      router.start(chunks.stream);
      await router.dispose();

      chunks.add(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      expect(router.isActive, isFalse);
      expect(bridge.commands, isEmpty);
    });
  });
}

class _FakeAudioIsolateBridge implements AudioIsolateBridge {
  bool available = true;
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
    available = true;
    return Future<bool>.value(true);
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
