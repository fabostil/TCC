import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/observability/runtime_telemetry_tracer.dart';
import 'package:app_voz/features/voices/realtime/tts/intent_response_formatter.dart';
import 'package:app_voz/features/voices/realtime/tts/text_to_speech_engine.dart';
import 'package:app_voz/features/voices/realtime/tts/voice_response_bridge.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceResponseBridge', () {
    late VoiceRealtimeEventBus bus;
    late _FakeTextToSpeechEngine tts;
    late VoiceResponseBridge bridge;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      tts = _FakeTextToSpeechEngine();
      bridge = VoiceResponseBridge(eventBus: bus, ttsEngine: tts)..start();
    });

    tearDown(() async {
      await bridge.dispose();
    });

    test(
      'responde a MetronomeIntent com texto e correlationId corretos',
      () async {
        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'intent-flow',
            intent: const MetronomeIntent(bpm: 120, rawText: 'metronomo 120'),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tts.calls, hasLength(1));
        expect(
          tts.calls.single.text,
          'Ajustando metronomo para 120 batidas por minuto',
        );
        expect(tts.calls.single.correlationId, 'intent-flow');
      },
    );

    test('responde defensivamente a UnknownIntent', () async {
      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'unknown-flow',
          intent: const UnknownIntent('texto sem comando'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        tts.calls.single.text,
        'Desculpe, não consegui entender o comando musical. Você pode tentar dizer tocar, pausar ou mudar o metrônomo.',
      );
      expect(tts.calls.single.correlationId, 'unknown-flow');
    });

    test('formatter gera resposta instrutiva exata para UnknownIntent', () {
      expect(
        const IntentResponseFormatter().format(
          const UnknownIntent('texto sem comando'),
        ),
        'Desculpe, não consegui entender o comando musical. Você pode tentar dizer tocar, pausar ou mudar o metrônomo.',
      );
    });

    test('responde UnknownIntent duplicado uma vez por correlationId', () async {
      final first = VoiceCommandInterpretedEvent(
        source: 'test',
        correlationId: 'unknown-duplicate-flow',
        intent: const UnknownIntent('texto sem comando'),
      );
      final second = VoiceCommandInterpretedEvent(
        source: 'test',
        correlationId: 'unknown-duplicate-flow',
        intent: const UnknownIntent('outro texto sem comando'),
      );

      bus.publish(first);
      bus.publish(second);
      await Future<void>.delayed(Duration.zero);

      expect(tts.calls, hasLength(1));
      expect(
        tts.calls.single.text,
        'Desculpe, não consegui entender o comando musical. Você pode tentar dizer tocar, pausar ou mudar o metrônomo.',
      );
      expect(tts.calls.single.correlationId, 'unknown-duplicate-flow');
    });

    test(
      'captura falha de speak, registra telemetria e continua operacional',
      () async {
        final tracer = RuntimeTelemetryTracer(eventBus: bus);
        tts.failNextSpeak = true;

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'failing-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final degraded = bus.timeline
            .whereType<VoiceSystemDegradedEvent>()
            .single;
        expect(degraded.reason, 'tts_speak_failed');
        expect(degraded.correlationId, 'failing-flow');
        expect(
          tracer
              .getTraceChain('failing-flow')
              .where(
                (event) =>
                    event.type == VoiceRealtimeEventType.voiceSystemDegraded,
              ),
          isNotEmpty,
        );

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'next-flow',
            intent: const PlaybackIntent(action: 'pause', rawText: 'pause'),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tts.calls.map((call) => call.correlationId), [
          'failing-flow',
          'next-flow',
        ]);
        expect(tts.calls.last.text, 'Pausando a musica');

        await tracer.dispose();
      },
    );

    test('ignora respostas duplicadas para o mesmo correlationId', () async {
      final first = VoiceCommandInterpretedEvent(
        source: 'test',
        correlationId: 'duplicate-flow',
        intent: const PlaybackIntent(action: 'start', rawText: 'play'),
      );
      final second = VoiceCommandInterpretedEvent(
        source: 'test',
        correlationId: 'duplicate-flow',
        intent: const MetronomeIntent(bpm: 140, rawText: 'metronomo 140'),
      );

      bus.publish(first);
      bus.publish(second);
      await Future<void>.delayed(Duration.zero);

      expect(tts.calls, hasLength(1));
      expect(tts.calls.single.text, 'Iniciando reproducao');
    });

    test(
      'responde a VoiceCommandFailedEvent usando formatFailure e correlationId',
      () async {
        await bridge.dispose();
        final formatter = _SpyIntentResponseFormatter();
        bridge = VoiceResponseBridge(
          eventBus: bus,
          ttsEngine: tts,
          formatter: formatter,
        )..start();

        bus.publish(
          VoiceCommandFailedEvent(
            source: 'test',
            reason: 'no_track_selected',
            correlationId: 'failure-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(formatter.failureReasons, ['no_track_selected']);
        expect(tts.calls, hasLength(1));
        expect(
          tts.calls.single.text,
          'Nenhuma gravação foi selecionada no editor para reproduzir.',
        );
        expect(tts.calls.single.correlationId, 'failure-flow');
      },
    );

    test(
      'responde pedido de confirmacao de exclusao com correlationId',
      () async {
        bus.publish(
          VoiceCommandConfirmationRequiredEvent(
            source: 'test',
            action: 'delete_last_recording',
            correlationId: 'confirm-flow',
            intent: const DeleteLastRecordingIntent(
              rawText: 'deletar ultima gravacao',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tts.calls, hasLength(1));
        expect(
          tts.calls.single.text,
          'Confirmar exclusão da última gravação? Diga confirmar ou cancelar.',
        );
        expect(tts.calls.single.correlationId, 'confirm-flow');
      },
    );

    test(
      'responde cancelamento de exclusao resolvido com correlationId',
      () async {
        bus.publish(
          VoiceCommandConfirmationResolvedEvent(
            source: 'test',
            action: 'delete_last_recording',
            approved: false,
            correlationId: 'delete-flow',
            intent: const DeleteLastRecordingIntent(
              rawText: 'deletar ultima gravacao',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tts.calls, hasLength(1));
        expect(
          tts.calls.single.text,
          'Exclusão cancelada. A gravação foi mantida.',
        );
        expect(tts.calls.single.correlationId, 'delete-flow');
      },
    );
  });
}

class _SpyIntentResponseFormatter extends IntentResponseFormatter {
  final List<String> failureReasons = [];

  @override
  String formatFailure(String reason) {
    failureReasons.add(reason);
    return super.formatFailure(reason);
  }
}

class _FakeTextToSpeechEngine implements TextToSpeechEngine {
  final List<_SpeakCall> calls = [];
  var failNextSpeak = false;
  var disposed = false;
  var stopped = false;

  @override
  Future<void> speak(String text, String correlationId) async {
    calls.add(_SpeakCall(text: text, correlationId: correlationId));
    stopped = false;
    if (failNextSpeak) {
      failNextSpeak = false;
      throw StateError('tts failed');
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _SpeakCall {
  const _SpeakCall({required this.text, required this.correlationId});

  final String text;
  final String correlationId;
}
