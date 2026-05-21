import 'package:app_voz/features/voices/realtime/runtime/runtime_registry.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceRuntimeRegistry', () {
    late VoiceRuntimeRegistry registry;
    late VoiceRealtimeEventBus bus;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      registry = VoiceRuntimeRegistry(eventBus: bus);
    });

    test('registra owner, rota/contexto e sessao de voz ativa', () {
      registry.setActiveOwner('home');
      registry.registerRouteContext(
        routeId: 'home_route',
        routeName: '/home',
        metadata: {'tab': 'main'},
      );

      final token = registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => true,
        recover: () async {},
      );

      expect(registry.activeOwnerId, 'home');
      expect(registry.activeRouteContext?.routeId, 'home_route');
      expect(registry.activeRouteContext?.metadata['tab'], 'main');
      expect(registry.activeVoiceSession?.ownerId, 'home');
      expect(
        registry.isVoiceSessionActive(ownerId: 'home', token: token),
        isTrue,
      );
    });

    test(
      'descarta sessao quando a referencia da pagina deixa de estar viva',
      () {
        var alive = true;

        final token = registry.registerVoiceSession(
          ownerId: 'editor',
          shouldRecover: () => true,
          recover: () async {},
          isAlive: () => alive,
        );

        expect(
          registry.isVoiceSessionActive(ownerId: 'editor', token: token),
          isTrue,
        );

        alive = false;

        expect(registry.activeVoiceSession, isNull);
        expect(
          registry.isVoiceSessionActive(ownerId: 'editor', token: token),
          isFalse,
        );
      },
    );

    test('nao recupera sessao obsoleta apos novo registro', () async {
      var recovered = false;
      final oldToken = registry.registerVoiceSession(
        ownerId: 'home',
        shouldRecover: () => true,
        recover: () async {
          recovered = true;
        },
      );
      final newToken = registry.registerVoiceSession(
        ownerId: 'dashboard',
        shouldRecover: () => true,
        recover: () async {},
      );

      final oldRecovered = await registry.recoverVoiceSession(
        ownerId: 'home',
        token: oldToken,
      );

      expect(oldRecovered, isFalse);
      expect(recovered, isFalse);
      expect(
        registry.isVoiceSessionActive(ownerId: 'dashboard', token: newToken),
        isTrue,
      );
    });

    test('limpa sessao quando contexto de rota ativo e descartado', () {
      registry.registerRouteContext(routeId: 'editor_route');
      registry.registerVoiceSession(
        ownerId: 'editor',
        shouldRecover: () => true,
        recover: () async {},
      );

      registry.clearRouteContext(routeId: 'editor_route');

      expect(registry.activeRouteContext, isNull);
      expect(registry.activeVoiceSession, isNull);
    });

    test(
      'resolve requisicoes concorrentes de ownership deterministicamente',
      () {
        final first = VoiceOwnershipRequestedEvent(
          source: 'test',
          requesterId: 'home',
          correlationId: 'ownership-flow',
        );
        final second = VoiceOwnershipRequestedEvent(
          source: 'test',
          requesterId: 'dashboard',
          correlationId: 'ownership-flow',
        );

        bus.publish(first);
        bus.publish(second);

        expect(registry.ownership.ownerId, 'home');
        expect(
          bus.timeline.whereType<VoiceOwnershipGrantedEvent>(),
          hasLength(1),
        );
        final rejected = bus.timeline
            .whereType<VoiceOwnershipRejectedEvent>()
            .single;
        expect(rejected.metadata['requesterId'], 'dashboard');
        expect(rejected.metadata['activeOwnerId'], 'home');
        expect(rejected.causationId, second.id);
      },
    );

    test('revoga ownership ativo de forma rastreavel', () {
      bus.publish(
        VoiceOwnershipRequestedEvent(
          source: 'test',
          requesterId: 'editor',
          correlationId: 'ownership-revoke',
        ),
      );

      registry.revokeOwnership(
        ownerId: 'editor',
        correlationId: 'ownership-revoke',
        reason: 'route_change',
      );

      expect(registry.ownership.isOwned, isFalse);
      final revoked = bus.timeline
          .whereType<VoiceOwnershipRevokedEvent>()
          .single;
      expect(revoked.ownerId, 'editor');
      expect(revoked.correlationId, 'ownership-revoke');
    });
  });
}
