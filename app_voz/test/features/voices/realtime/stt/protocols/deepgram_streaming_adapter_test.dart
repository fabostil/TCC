import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/stt/cloud_streaming_speech_recognizer.dart';
import 'package:app_voz/features/voices/realtime/stt/protocols/deepgram_streaming_adapter.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepgramStreamingAdapter', () {
    test('monta endpoint com parametros e header de autenticacao', () async {
      final bus = VoiceRealtimeEventBus();
      final transport = _FakeWebSocketTransport();
      Uri? connectedUri;
      Map<String, dynamic>? connectedHeaders;
      final adapter = DeepgramStreamingAdapter(
        apiKey: 'dg-test-key',
        endpoint: Uri.parse('wss://api.deepgram.com/v1/listen'),
      );
      final recognizer = adapter.createRecognizer(
        eventBus: bus,
        connector:
            (uri, {timeout = const Duration(seconds: 5), headers}) async {
              connectedUri = uri;
              connectedHeaders = headers;
              return transport;
            },
      );

      await recognizer.startRecognition('dg-flow');

      expect(connectedHeaders, {'Authorization': 'Token dg-test-key'});
      expect(connectedUri?.queryParameters['model'], 'nova-2');
      expect(connectedUri?.queryParameters['encoding'], 'linear16');
      expect(connectedUri?.queryParameters['sample_rate'], '16000');
      expect(connectedUri?.queryParameters['channels'], '1');
      expect(connectedUri?.queryParameters['interim_results'], 'true');
      expect(connectedUri?.queryParameters['punctuate'], 'true');

      await recognizer.dispose();
    });

    test('extrai transcript e is_final do payload real da Deepgram', () {
      final partial = DeepgramStreamingAdapter.parseServerResponse('''
        {
          "type": "Results",
          "is_final": false,
          "channel": {
            "alternatives": [
              {"transcript": "abrir gravacoes", "confidence": 0.97}
            ]
          }
        }
        ''');
      final finalResult = DeepgramStreamingAdapter.parseServerResponse('''
        {
          "type": "Results",
          "is_final": true,
          "channel": {
            "alternatives": [
              {"transcript": "salvar ideia musical", "confidence": 0.99}
            ]
          }
        }
        ''');

      expect(partial?.text, 'abrir gravacoes');
      expect(partial?.isFinal, isFalse);
      expect(finalResult?.text, 'salvar ideia musical');
      expect(finalResult?.isFinal, isTrue);
    });

    test('ignora payloads sem transcricao util ou JSON malformado', () {
      final ignoredPayloads = [
        '{"type":"Metadata","request_id":"abc"}',
        '{"is_final":false,"channel":{"alternatives":[]}}',
        '{"is_final":false,"channel":{"alternatives":[{"transcript":""}]}}',
        '{"is_final":false,"channel":{"alternatives":[{"transcript":"   "}]}}',
        '{"is_final":false,"channel":{"alternatives":[{}]}}',
        'not-json',
      ];

      for (final payload in ignoredPayloads) {
        expect(DeepgramStreamingAdapter.parseServerResponse(payload), isNull);
      }
    });

    test(
      'recognizer publica eventos usando parser Deepgram e CloseStream',
      () async {
        final bus = VoiceRealtimeEventBus();
        final transport = _FakeWebSocketTransport();
        final adapter = DeepgramStreamingAdapter(
          apiKey: 'dg-test-key',
          endpoint: Uri.parse('wss://api.deepgram.com/v1/listen'),
        );
        final recognizer = adapter.createRecognizer(
          eventBus: bus,
          connector:
              (_, {timeout = const Duration(seconds: 5), headers}) async {
                return transport;
              },
        );

        await recognizer.startRecognition('dg-flow');
        recognizer.feedAudioChunk(Uint8List.fromList([1, 2, 3]));
        transport.emit(
          '{"channel":{"alternatives":[{"transcript":"novo projeto"}]},"is_final":false}',
        );
        transport.emit(
          '{"channel":{"alternatives":[{"transcript":"abrir dashboard"}]},"is_final":true}',
        );
        await Future<void>.delayed(Duration.zero);
        await recognizer.stopRecognition();

        final results = bus.timeline.whereType<SpeechResultReceivedEvent>();
        expect(results.map((event) => event.metadata['text']), [
          'novo projeto',
          'abrir dashboard',
        ]);
        expect(results.map((event) => event.isFinal), [false, true]);
        expect(results.map((event) => event.correlationId), [
          'dg-flow',
          'dg-flow',
        ]);
        expect(transport.sent.first, isA<Uint8List>());
        expect(
          transport.sent.last,
          DeepgramStreamingAdapter.closeStreamMessage,
        );
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

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    await _controller.close();
  }
}
