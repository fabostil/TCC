import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/stt/cloud_streaming_speech_recognizer.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudStreamingSpeechRecognizer', () {
    test('envia chunks binarios pelo transporte WebSocket injetado', () async {
      final bus = VoiceRealtimeEventBus();
      final transport = _FakeWebSocketTransport();
      final recognizer = CloudStreamingSpeechRecognizer(
        endpoint: Uri.parse('wss://stt.example.test/stream'),
        eventBus: bus,
        connector:
            (uri, {timeout = const Duration(seconds: 5), headers}) async {
              expect(uri.toString(), 'wss://stt.example.test/stream');
              return transport;
            },
      );

      await recognizer.startRecognition('cloud-flow');
      recognizer.feedAudioChunk(Uint8List.fromList([1, 2, 3, 4]));

      expect(transport.sent, hasLength(1));
      expect(transport.sent.single, isA<Uint8List>());
      expect((transport.sent.single as Uint8List).toList(), [1, 2, 3, 4]);

      await recognizer.dispose();
    });

    test(
      'publica resultados parciais e finais com correlationId original',
      () async {
        final bus = VoiceRealtimeEventBus();
        final transport = _FakeWebSocketTransport();
        final recognizer = CloudStreamingSpeechRecognizer(
          endpoint: Uri.parse('wss://stt.example.test/stream'),
          eventBus: bus,
          connector:
              (_, {timeout = const Duration(seconds: 5), headers}) async {
                return transport;
              },
        );

        await recognizer.startRecognition('cloud-flow');
        transport.emit('{"text":"tocando baixo","isFinal":false}');
        transport.emit('{"transcript":"tocando baixo final","is_final":true}');
        await Future<void>.delayed(Duration.zero);

        final results = bus.timeline.whereType<SpeechResultReceivedEvent>();
        expect(results.map((event) => event.correlationId), [
          'cloud-flow',
          'cloud-flow',
        ]);
        expect(results.map((event) => event.metadata['text']), [
          'tocando baixo',
          'tocando baixo final',
        ]);
        expect(results.map((event) => event.isFinal), [false, true]);

        await recognizer.dispose();
      },
    );

    test('publica falha quando handshake excede timeout', () async {
      final bus = VoiceRealtimeEventBus();
      final recognizer = CloudStreamingSpeechRecognizer(
        endpoint: Uri.parse('wss://stt.example.test/stream'),
        eventBus: bus,
        handshakeTimeout: const Duration(milliseconds: 10),
        connector: (_, {timeout = const Duration(seconds: 5), headers}) {
          return Completer<WebSocketTransport>().future;
        },
      );

      await recognizer.startRecognition('timeout-flow');
      await Future<void>.delayed(Duration.zero);

      final failures = bus.timeline.whereType<SpeechListeningFailedEvent>();
      expect(failures, hasLength(1));
      expect(failures.single.correlationId, 'timeout-flow');
      expect(failures.single.reason, contains('TimeoutException'));

      await recognizer.dispose();
    });

    test(
      'ignora chunks quando socket fecha e publica falha inesperada',
      () async {
        final bus = VoiceRealtimeEventBus();
        final transport = _FakeWebSocketTransport();
        final recognizer = CloudStreamingSpeechRecognizer(
          endpoint: Uri.parse('wss://stt.example.test/stream'),
          eventBus: bus,
          connector:
              (_, {timeout = const Duration(seconds: 5), headers}) async {
                return transport;
              },
        );

        await recognizer.startRecognition('drop-flow');
        await transport.closeUnexpectedly();
        await Future<void>.delayed(Duration.zero);

        recognizer.feedAudioChunk(Uint8List.fromList([9, 9, 9]));

        expect(transport.sent, isEmpty);
        final failures = bus.timeline.whereType<SpeechListeningFailedEvent>();
        expect(failures.single.correlationId, 'drop-flow');
        expect(failures.single.reason, 'websocket_closed_unexpectedly');

        await recognizer.dispose();
      },
    );
  });
}

class _FakeWebSocketTransport implements WebSocketTransport {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final List<Object?> sent = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(Object? data) {
    if (closed) {
      throw StateError('socket closed');
    }
    sent.add(data);
  }

  void emit(String message) {
    _controller.add(message);
  }

  Future<void> closeUnexpectedly() async {
    closed = true;
    await _controller.close();
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    await _controller.close();
  }
}
