import 'package:app_voz/features/voices/realtime/dispatch/contratos/audio_output_guard.dart';
import 'package:app_voz/features/voices/realtime/tts/adapters/flutter_tts_engine.dart';
import 'package:app_voz/features/voices/realtime/tts/text_to_speech_engine.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterTtsEngine', () {
    test(
      'configura idiomas, parametros e guarda de audio antes de falar',
      () async {
        final client = _FakeFlutterTtsClient(
          languages: ['en-US', 'pt-BR', 'pt'],
        );
        final guard = _FakeAudioOutputGuard();
        final engine = FlutterTtsEngine(
          eventBus: VoiceRealtimeEventBus(),
          client: client,
          audioOutputGuard: guard,
        );

        await engine.speak('Projeto criado.', 'tts-flow');

        expect(client.calls, [
          const _TtsCall('stop'),
          const _TtsCall('awaitSpeakCompletion', false),
          const _TtsCall('getLanguages'),
          const _TtsCall('setLanguage', 'pt-BR'),
          const _TtsCall('setSpeechRate', 0.5),
          const _TtsCall('setPitch', 1.0),
          const _TtsCall('setVolume', 1.0),
          const _TtsCall('speak', 'Projeto criado.'),
        ]);
        expect(guard.beginCalls, ['flutter_tts_engine:tts_speak_started']);
        expect(guard.endCalls, isEmpty);

        client.complete();
        expect(guard.endCalls, ['flutter_tts_engine:tts_completion']);

        await engine.dispose();

        final portugueseFallbackClient = _FakeFlutterTtsClient(
          languages: ['en-US', 'pt'],
        );
        final portugueseFallbackEngine = FlutterTtsEngine(
          eventBus: VoiceRealtimeEventBus(),
          client: portugueseFallbackClient,
          audioOutputGuard: _FakeAudioOutputGuard(),
        );

        await portugueseFallbackEngine.speak('Tudo pronto.', 'tts-pt');

        expect(
          portugueseFallbackClient.calls.singleWhere(
            (call) => call.method == 'setLanguage',
          ),
          const _TtsCall('setLanguage', 'pt'),
        );

        await portugueseFallbackEngine.dispose();

        final systemFallbackClient = _FakeFlutterTtsClient(
          languages: ['en-US', 'es-ES'],
        );
        final systemFallbackEngine = FlutterTtsEngine(
          eventBus: VoiceRealtimeEventBus(),
          client: systemFallbackClient,
          audioOutputGuard: _FakeAudioOutputGuard(),
        );

        await systemFallbackEngine.speak('Tudo pronto.', 'tts-default');

        expect(
          systemFallbackClient.calls.singleWhere(
            (call) => call.method == 'setLanguage',
          ),
          const _TtsCall('setLanguage', 'en-US'),
        );

        await systemFallbackEngine.dispose();

        final overlappingClient = _FakeFlutterTtsClient(languages: ['pt-BR']);
        final overlappingGuard = _FakeAudioOutputGuard();
        final overlappingEngine = FlutterTtsEngine(
          eventBus: VoiceRealtimeEventBus(),
          client: overlappingClient,
          audioOutputGuard: overlappingGuard,
        );

        await overlappingEngine.speak('Primeira fala.', 'first');
        await overlappingEngine.speak('Segunda fala.', 'second');

        expect(
          overlappingClient.calls.where((call) => call.method == 'stop'),
          hasLength(2),
        );
        expect(overlappingGuard.endCalls.first, 'flutter_tts_engine:tts_stop');

        await overlappingEngine.dispose();
      },
    );

    test('usa fallback quando o plugin nativo nao esta registrado', () async {
      final fallback = _FakeTextToSpeechEngine();
      final engine = FlutterTtsEngine(
        eventBus: VoiceRealtimeEventBus(),
        client: _FakeFlutterTtsClient(languages: ['pt-BR'], failOnStop: true),
        fallback: fallback,
        audioOutputGuard: _FakeAudioOutputGuard(),
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

class _FakeFlutterTtsClient implements FlutterTtsClient {
  _FakeFlutterTtsClient({required this.languages, this.failOnStop = false});

  final List<String> languages;
  final bool failOnStop;
  final List<_TtsCall> calls = [];
  VoidCallback? completionHandler;
  VoidCallback? cancelHandler;
  Function(dynamic message)? errorHandler;

  void complete() {
    completionHandler?.call();
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add(_TtsCall('awaitSpeakCompletion', awaitCompletion));
  }

  @override
  Future<dynamic> getLanguages() async {
    calls.add(const _TtsCall('getLanguages'));
    return languages;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add(_TtsCall('setLanguage', language));
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add(_TtsCall('setPitch', pitch));
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add(_TtsCall('setSpeechRate', rate));
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add(_TtsCall('setVolume', volume));
  }

  @override
  Future<dynamic> speak(String text) async {
    calls.add(_TtsCall('speak', text));
  }

  @override
  Future<dynamic> stop() async {
    calls.add(const _TtsCall('stop'));
    if (failOnStop) {
      throw MissingPluginException('missing flutter_tts');
    }
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    cancelHandler = callback;
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    completionHandler = callback;
  }

  @override
  void setErrorHandler(Function(dynamic message) handler) {
    errorHandler = handler;
  }
}

class _FakeAudioOutputGuard implements AudioOutputGuard {
  final List<String> beginCalls = [];
  final List<String> endCalls = [];
  var available = true;

  @override
  bool isAudioOutputAvailable() => available;

  @override
  Future<bool> beginAudioOutput({
    required String ownerId,
    String? reason,
  }) async {
    beginCalls.add('$ownerId:$reason');
    return available;
  }

  @override
  void endAudioOutput({required String ownerId, String? reason}) {
    endCalls.add('$ownerId:$reason');
  }
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

class _TtsCall {
  const _TtsCall(this.method, [this.arguments]);

  final String method;
  final Object? arguments;

  @override
  bool operator ==(Object other) {
    return other is _TtsCall &&
        other.method == method &&
        other.arguments == arguments;
  }

  @override
  int get hashCode => Object.hash(method, arguments);

  @override
  String toString() => '_TtsCall($method, $arguments)';
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
