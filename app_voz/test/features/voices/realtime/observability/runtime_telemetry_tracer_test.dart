import 'package:app_voz/features/voices/realtime/observability/runtime_telemetry_tracer.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeTelemetryTracer', () {
    late VoiceRealtimeEventBus bus;
    late RuntimeTelemetryTracer tracer;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      tracer = RuntimeTelemetryTracer(eventBus: bus, capacity: 3);
    });

    tearDown(() async {
      await tracer.dispose();
    });

    test('reconstroi cadeia por correlationId e causationId', () {
      final root = SilenceDetectedEvent(
        source: 'test',
        ownerId: 'editor',
        correlationId: 'flow-trace',
        silenceMs: 6000,
        level: -41,
      );
      final stop = StopVoiceCaptureRequestedEvent(
        source: 'runtime_engine',
        ownerId: 'editor',
        correlationId: 'flow-trace',
        causationId: root.id,
      );
      final recovery = RecoverVoiceSessionRequestedEvent(
        source: 'runtime_engine',
        ownerId: 'editor',
        correlationId: 'flow-trace',
        causationId: root.id,
      );
      final unrelated = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'player',
        correlationId: 'other-flow',
      );

      bus.publish(root);
      bus.publish(stop);
      bus.publish(unrelated);
      bus.publish(recovery);

      final chain = tracer.getTraceChain('flow-trace');

      expect(chain, [root, stop, recovery]);
      expect(
        chain.every((event) => event.correlationId == 'flow-trace'),
        isTrue,
      );
      expect(
        chain.skip(1).every((event) => event.causationId == root.id),
        isTrue,
      );
    });

    test('mantem buffer circular de tamanho fixo', () {
      final first = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'one',
        correlationId: 'first',
      );
      final second = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'two',
        correlationId: 'second',
      );
      final third = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'three',
        correlationId: 'third',
      );
      final fourth = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'four',
        correlationId: 'fourth',
      );

      bus.publish(first);
      bus.publish(second);
      bus.publish(third);
      bus.publish(fourth);

      expect(tracer.length, 3);
      expect(tracer.getTraceChain('first'), isEmpty);
      expect(tracer.getTraceChain('second'), [second]);
      expect(tracer.getTraceChain('fourth'), [fourth]);
    });
  });
}
