import 'package:app_voz/features/voices/realtime/runtime/runtime_engine.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_registry.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_recovery_policy.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceRuntimeEngine', () {
    late VoiceRealtimeEventBus bus;
    late VoiceRuntimeRegistry registry;
    late VoiceRuntimeEngine engine;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      registry = VoiceRuntimeRegistry(eventBus: bus);
      engine = VoiceRuntimeEngine(
        eventBus: bus,
        registry: registry,
        defaultRecoveryDelay: Duration.zero,
      )..start();
    });

    tearDown(() async {
      await engine.stop();
    });

    test('reage a SilenceDetected solicitando stop e recovery rastreaveis', () {
      final token = registry.registerVoiceSession(
        ownerId: 'editor',
        shouldRecover: () => true,
        recover: () async {},
      );
      final silence = SilenceDetectedEvent(
        source: 'test',
        ownerId: 'editor',
        reason: 'automatic_silence_stop',
        correlationId: 'flow-silence',
        silenceMs: 6000,
        level: -42,
      );

      bus.publish(silence);

      final stopRequested = bus.timeline
          .whereType<StopVoiceCaptureRequestedEvent>()
          .single;
      expect(stopRequested.correlationId, silence.correlationId);
      expect(stopRequested.causationId, silence.id);
      expect(stopRequested.metadata['sessionToken'], token);

      final requested = bus.timeline
          .whereType<RecoverVoiceSessionRequestedEvent>()
          .single;
      expect(requested.correlationId, silence.correlationId);
      expect(requested.causationId, silence.id);
      expect(requested.metadata['sessionToken'], token);
    });

    test('agenda, tenta e confirma recovery solicitado por evento', () async {
      var recovered = false;
      final token = registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => true,
        recover: () async {
          recovered = true;
        },
      );
      final request = RecoverVoiceSessionRequestedEvent(
        source: 'test',
        ownerId: 'home',
        reason: 'normal',
        correlationId: 'flow-recovery',
        metadata: {'delayMs': 0, 'sessionToken': token},
      );

      bus.publish(request);
      await Future<void>.delayed(Duration.zero);

      expect(recovered, isTrue);
      expect(
        bus.eventsForCorrelation('flow-recovery').map((event) => event.type),
        containsAllInOrder([
          VoiceRealtimeEventType.recoverVoiceSessionRequested,
          VoiceRealtimeEventType.recoveryScheduled,
          VoiceRealtimeEventType.recoveryAttempted,
          VoiceRealtimeEventType.voiceSessionRecovered,
        ]),
      );
      final recoveredEvent = bus.timeline
          .whereType<VoiceSessionRecoveredEvent>()
          .single;
      expect(recoveredEvent.correlationId, request.correlationId);
      expect(recoveredEvent.causationId, isNotNull);
    });

    test('ignora recovery quando cadeia foi cancelada', () async {
      var recovered = false;
      final token = registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => true,
        recover: () async {
          recovered = true;
        },
      );
      bus.cancelChain('flow-cancelled', source: 'test');

      final published = bus.publish(
        RecoverVoiceSessionRequestedEvent(
          source: 'test',
          ownerId: 'home',
          correlationId: 'flow-cancelled',
          metadata: {'delayMs': 0, 'sessionToken': token},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(published, isFalse);
      expect(recovered, isFalse);
      expect(bus.timeline.whereType<RecoveryAttemptedEvent>(), isEmpty);
    });

    test('publica skipped quando nao ha sessao ativa para silencio', () {
      final silence = SilenceDetectedEvent(
        source: 'test',
        ownerId: 'editor',
        correlationId: 'flow-no-session',
        silenceMs: 6000,
        level: -44,
      );

      bus.publish(silence);

      final skipped = bus.timeline.whereType<RecoverySkippedEvent>().single;
      expect(skipped.reason, 'no_active_voice_session');
      expect(skipped.correlationId, silence.correlationId);
      expect(skipped.causationId, silence.id);
    });

    test(
      'nao executa recovery quando registry considera sessao obsoleta',
      () async {
        var recovered = false;
        var alive = true;
        final token = registry.registerVoiceSession(
          ownerId: 'home',
          shouldRecover: () => true,
          recover: () async {
            recovered = true;
          },
          isAlive: () => alive,
        );
        alive = false;

        bus.publish(
          RecoverVoiceSessionRequestedEvent(
            source: 'test',
            ownerId: 'home',
            correlationId: 'flow-stale',
            metadata: {'delayMs': 0, 'sessionToken': token},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(recovered, isFalse);
        final skipped = bus.timeline.whereType<RecoverySkippedEvent>().single;
        expect(skipped.reason, 'stale_voice_session');
      },
    );

    test('aciona pipeline de recovery quando STT falha', () async {
      var recovered = false;
      final token = registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => true,
        recover: () async {
          recovered = true;
        },
      );
      final failure = SpeechListeningFailedEvent(
        source: 'test',
        ownerId: 'home',
        reason: 'network',
        message: 'Falha tecnica STT.',
        correlationId: 'flow-stt-failed',
      );

      bus.publish(failure);
      await Future<void>.delayed(Duration.zero);

      final requested = bus.timeline
          .whereType<RecoverVoiceSessionRequestedEvent>()
          .single;
      expect(requested.correlationId, failure.correlationId);
      expect(requested.causationId, failure.id);
      expect(requested.metadata['sessionToken'], token);
      expect(requested.metadata['failureReason'], 'network');
      expect(recovered, isTrue);
      expect(
        bus.eventsForCorrelation('flow-stt-failed').map((event) => event.type),
        containsAll([
          VoiceRealtimeEventType.recoveryScheduled,
          VoiceRealtimeEventType.recoveryAttempted,
          VoiceRealtimeEventType.voiceSessionRecovered,
        ]),
      );
    });

    test(
      'nao processa novamente a mesma falha STT por correlationId',
      () async {
        registry.registerVoiceSession(
          ownerId: 'home',
          shouldRecover: () => true,
          recover: () async {},
        );

        bus.publish(
          SpeechListeningFailedEvent(
            source: 'test',
            ownerId: 'home',
            reason: 'timeout',
            correlationId: 'same-failure',
          ),
        );
        bus.publish(
          SpeechListeningFailedEvent(
            source: 'test',
            ownerId: 'home',
            reason: 'timeout',
            correlationId: 'same-failure',
          ),
        );

        expect(
          bus.timeline.whereType<RecoverVoiceSessionRequestedEvent>(),
          hasLength(1),
        );
      },
    );

    test('degrada sistema apos estouro do budget de recovery', () async {
      await engine.stop();
      engine = VoiceRuntimeEngine(
        eventBus: bus,
        registry: registry,
        recoveryPolicy: RuntimeRecoveryPolicy(
          maxAttempts: 2,
          baseBackoff: Duration.zero,
        ),
        defaultRecoveryDelay: Duration.zero,
      )..start();
      registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => false,
        recover: () async {},
      );

      for (final correlationId in ['fail-1', 'fail-2', 'fail-3']) {
        bus.publish(
          SpeechListeningFailedEvent(
            source: 'test',
            ownerId: 'home',
            reason: 'timeout',
            correlationId: correlationId,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      final degraded = bus.timeline
          .whereType<VoiceSystemDegradedEvent>()
          .single;
      expect(degraded.reason, 'recovery_budget_exhausted');
      expect(degraded.correlationId, 'fail-3');
      expect(degraded.metadata['maxAttempts'], 2);
      expect(registry.activeVoiceSession, isNull);
    });

    test('inclui snapshot imutavel de contexto no recovery por falha STT', () {
      registry.registerRouteContext(
        routeId: 'editor',
        routeName: '/editor',
        metadata: {'voiceRuntimeAllowed': true, 'projectId': 7},
      );
      final token = registry.registerVoiceSession(
        ownerId: 'editor',
        shouldRecover: () => true,
        recover: () async {},
        metadata: {'mode': 'recording_ready'},
      );

      final failure = SpeechListeningFailedEvent(
        source: 'test',
        ownerId: 'editor',
        reason: 'timeout',
        correlationId: 'snapshot-flow',
      );
      bus.publish(failure);

      final requested = bus.timeline
          .whereType<RecoverVoiceSessionRequestedEvent>()
          .single;
      final snapshot = requested.metadata['contextSnapshot'];

      expect(snapshot, isA<Map<String, Object?>>());
      final metadata = snapshot as Map<String, Object?>;
      expect(metadata['activeOwnerId'], 'editor');
      expect(metadata['ownershipOwnerId'], 'editor');
      expect(metadata['routeId'], 'editor');
      expect(metadata['routeName'], '/editor');
      expect(metadata['sessionToken'], token);
      expect(metadata['sessionOwnerId'], 'editor');
      expect(metadata['sessionMetadata'], {'mode': 'recording_ready'});
      expect(metadata['routeMetadata'], {
        'voiceRuntimeAllowed': true,
        'projectId': 7,
      });
    });

    test('descarta sessao ativa quando rota sai do escopo permitido', () {
      final token = registry.registerVoiceSession(
        ownerId: 'editor',
        shouldRecover: () => true,
        recover: () async {},
      );

      registry.registerRouteContext(
        routeId: 'login',
        routeName: '/login',
        metadata: {'voiceRuntimeAllowed': false},
      );

      final stopRequested = bus.timeline
          .whereType<StopVoiceCaptureRequestedEvent>()
          .single;
      expect(stopRequested.reason, 'route_out_of_scope');
      expect(stopRequested.ownerId, 'editor');
      expect(stopRequested.metadata['sessionToken'], token);
      expect(stopRequested.metadata['routeId'], 'login');
      expect(registry.activeVoiceSession, isNull);
    });

    test('rejeita comando mutavel externo sem ownership ativo', () {
      final command = StopVoiceCaptureRequestedEvent(
        source: 'contextual_mixin',
        ownerId: 'old-page',
        reason: 'manual_stop',
        correlationId: 'stop-orphan',
      );

      bus.publish(command);

      final rejected = bus.timeline
          .whereType<StopVoiceCaptureRejectedEvent>()
          .single;
      expect(rejected.reason, 'ownership_required');
      expect(rejected.correlationId, command.correlationId);
      expect(rejected.causationId, command.id);
      expect(rejected.metadata['eventSource'], 'contextual_mixin');
    });

    test('permite comando mutavel externo quando owner possui ownership', () {
      bus.publish(
        VoiceOwnershipRequestedEvent(
          source: 'test',
          requesterId: 'home',
          correlationId: 'owned-stop',
        ),
      );
      final command = StopVoiceCaptureRequestedEvent(
        source: 'contextual_mixin',
        ownerId: 'home',
        reason: 'manual_stop',
        correlationId: 'owned-stop',
      );

      bus.publish(command);

      expect(bus.timeline.whereType<StopVoiceCaptureRejectedEvent>(), isEmpty);
    });
  });
}
