import 'package:app_voz/features/voices/realtime/tts/adapters/flutter_tts_engine.dart';
import 'package:app_voz/features/voices/realtime/tts/text_to_speech_engine.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterTtsEngine', () {
    const channelName = 'test_flutter_tts_engine';
    late MethodChannel channel;

    setUp(() {
      channel = const MethodChannel(channelName);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('configura pt-BR, rate e pitch antes de falar', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'isLanguageAvailable') {
              return call.arguments == 'pt-BR';
            }
            return null;
          });

      final engine = FlutterTtsEngine(
        eventBus: VoiceRealtimeEventBus(),
        channel: channel,
      );

      await engine.speak('Projeto criado.', 'tts-flow');

      expect(calls.map((call) => call.method), [
        'stop',
        'awaitSpeakCompletion',
        'setQueueMode',
        'isLanguageAvailable',
        'setLanguage',
        'setSpeechRate',
        'setPitch',
        'speak',
      ]);
      expect(
        calls.singleWhere((call) => call.method == 'setLanguage').arguments,
        'pt-BR',
      );
      expect(
        calls.singleWhere((call) => call.method == 'setSpeechRate').arguments,
        0.5,
      );
      expect(
        calls.singleWhere((call) => call.method == 'setPitch').arguments,
        1.0,
      );
      expect(
        calls.singleWhere((call) => call.method == 'speak').arguments,
        'Projeto criado.',
      );

      await engine.dispose();
    });

    test('usa fallback quando o plugin nativo nao esta registrado', () async {
      final fallback = _FakeTextToSpeechEngine();
      final engine = FlutterTtsEngine(
        eventBus: VoiceRealtimeEventBus(),
        channel: channel,
        fallback: fallback,
      );

      await engine.speak('Falha ao gravar.', 'missing-plugin-flow');

      expect(fallback.calls, [
        const _SpeakCall(
          text: 'Falha ao gravar.',
          correlationId: 'missing-plugin-flow',
        ),
      ]);

      await engine.dispose();
      expect(fallback.disposed, isTrue);
    });
  });
}

class _FakeTextToSpeechEngine implements TextToSpeechEngine {
  final List<_SpeakCall> calls = [];
  var disposed = false;

  @override
  Future<void> speak(String text, String correlationId) async {
    calls.add(_SpeakCall(text: text, correlationId: correlationId));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _SpeakCall {
  const _SpeakCall({required this.text, required this.correlationId});

  final String text;
  final String correlationId;

  @override
  bool operator ==(Object other) {
    return other is _SpeakCall &&
        other.text == text &&
        other.correlationId == correlationId;
  }

  @override
  int get hashCode => Object.hash(text, correlationId);
}
