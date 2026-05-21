import 'package:app_voz/features/voices/realtime/voice_realtime_event.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceRealtimeEventBus', () {
    test('publica eventos e permite observacao por tipo concreto', () {
      final bus = VoiceRealtimeEventBus();
      final observed = <SpeechListeningStartedEvent>[];

      final subscription = bus.on<SpeechListeningStartedEvent>().listen(
        observed.add,
      );

      final event = SpeechListeningStartedEvent(
        source: 'test',
        ownerId: 'home',
        reason: 'auto_start',
      );

      expect(bus.publish(event), isTrue);
      expect(observed, hasLength(1));
      expect(observed.single.ownerId, 'home');
      expect(bus.latest, same(event));
      expect(bus.timeline, contains(event));

      subscription.cancel();
    });

    test('mantem timeline circular respeitando o limite configurado', () {
      final bus = VoiceRealtimeEventBus(maxEvents: 2);

      final first = PlaybackStartedEvent(source: 'test', ownerId: 'player');
      final second = PlaybackStoppedEvent(source: 'test', ownerId: 'player');
      final third = RecordingStartedEvent(source: 'test', ownerId: 'editor');

      bus.publish(first);
      bus.publish(second);
      bus.publish(third);

      expect(bus.timeline, hasLength(2));
      expect(bus.timeline, isNot(contains(first)));
      expect(bus.timeline.first, same(second));
      expect(bus.timeline.last, same(third));
    });

    test('preserva correlacao de cadeia de eventos', () {
      final bus = VoiceRealtimeEventBus();
      const correlationId = 'flow-recording-1';

      final started = RecordingStartedEvent(
        source: 'test',
        ownerId: 'editor',
        correlationId: correlationId,
      );
      final stopped = RecordingStoppedEvent(
        source: 'test',
        ownerId: 'editor',
        correlationId: correlationId,
        causationId: started.id,
      );
      final playback = PlaybackStartedEvent(
        source: 'test',
        ownerId: 'player',
        correlationId: 'flow-playback-1',
      );

      bus.publish(started);
      bus.publish(stopped);
      bus.publish(playback);

      final correlated = bus.eventsForCorrelation(correlationId);
      expect(correlated, [started, stopped]);
      expect(correlated.last.causationId, started.id);
    });

    test('cancela cadeia e bloqueia novos eventos cancelaveis', () {
      final bus = VoiceRealtimeEventBus();
      final observed = <VoiceRealtimeEvent>[];
      final subscription = bus.stream.listen(observed.add);
      const correlationId = 'recovery-flow';

      final scheduled = RecoveryScheduledEvent(
        source: 'test',
        ownerId: 'home',
        correlationId: correlationId,
      );
      final attempted = RecoveryAttemptedEvent(
        source: 'test',
        ownerId: 'home',
        correlationId: correlationId,
        causationId: scheduled.id,
      );

      expect(bus.publish(scheduled), isTrue);
      final cancellation = bus.cancelChain(
        correlationId,
        source: 'test',
        ownerId: 'home',
        reason: 'route_changed',
      );
      expect(bus.publish(attempted), isFalse);

      expect(bus.isChainCancelled(correlationId), isTrue);
      expect(bus.timeline, contains(scheduled));
      expect(bus.timeline, contains(cancellation));
      expect(bus.timeline, isNot(contains(attempted)));
      expect(observed, [scheduled, cancellation]);

      subscription.cancel();
    });

    test('permite observar eventos por enum de tipo canonico', () {
      final bus = VoiceRealtimeEventBus();
      final observed = <VoiceRealtimeEvent>[];
      final subscription = bus
          .onType(VoiceRealtimeEventType.voiceStateChanged)
          .listen(observed.add);

      final event = VoiceStateChangedEvent(
        source: 'test',
        previousState: 'idle',
        nextState: 'listening',
        ownerId: 'home',
      );

      bus.publish(event);

      expect(observed, [event]);
      expect(observed.single.metadata['previousState'], 'idle');
      expect(observed.single.metadata['nextState'], 'listening');

      subscription.cancel();
    });
  });
}
