import 'package:app_voz/features/voices/realtime/infrastructure/service/voice_foreground_service.dart';
import 'package:app_voz/features/voices/realtime/infrastructure/service/stub_voice_foreground_service.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_engine.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_registry.dart';
import 'package:app_voz/features/voices/realtime/runtime/voice_realtime_ecosystem.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contracts/voice_session_context_holder.dart';
import 'package:app_voz/features/voices/realtime/tts/text_to_speech_engine.dart';
import 'package:app_voz/features/voices/realtime/tts/voice_response_bridge.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceForegroundService lifecycle', () {
    late VoiceRealtimeEventBus bus;
    late VoiceRuntimeEngine runtimeEngine;
    late VoiceResponseBridge responseBridge;
    late _FakeVoiceForegroundService foregroundService;
    late VoiceRealtimeEcosystem ecosystem;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      runtimeEngine = VoiceRuntimeEngine(
        eventBus: bus,
        registry: VoiceRuntimeRegistry(eventBus: bus),
        useStreamFirstAudio: true,
      );
      responseBridge = VoiceResponseBridge(
        eventBus: bus,
        ttsEngine: _FakeTextToSpeechEngine(),
      );
      foregroundService = _FakeVoiceForegroundService();
      ecosystem = VoiceRealtimeEcosystem(
        eventBus: bus,
        runtimeEngine: runtimeEngine,
        responseBridge: responseBridge,
        foregroundService: foregroundService,
        useStreamFirstAudio: true,
      );
    });

    tearDown(() async {
      await ecosystem.stop();
      await runtimeEngine.dispose();
      await responseBridge.dispose();
    });

    test('inicia notificacao persistente quando realtime esta ativo', () async {
      await ecosystem.start();

      expect(runtimeEngine.isStarted, isTrue);
      expect(responseBridge.isStarted, isTrue);
      expect(foregroundService.startCalls, hasLength(1));
      expect(
        foregroundService.startCalls.single.title,
        VoiceRealtimeEcosystem.foregroundTitle,
      );
      expect(
        foregroundService.startCalls.single.message,
        VoiceRealtimeEcosystem.foregroundMessage,
      );
      expect(ecosystem.isForegroundStarted, isTrue);
    });

    test('encerra notificacao persistente ao parar o ecossistema', () async {
      await ecosystem.start();
      await ecosystem.stop();

      expect(foregroundService.stopCalls, 1);
      expect(ecosystem.isStarted, isFalse);
      expect(ecosystem.isForegroundStarted, isFalse);
    });

    test('nao aciona foreground service no fluxo legado', () async {
      final legacyService = _FakeVoiceForegroundService();
      final legacyRuntime = VoiceRuntimeEngine(
        eventBus: bus,
        registry: VoiceRuntimeRegistry(eventBus: bus),
        useStreamFirstAudio: false,
      );
      final legacyBridge = VoiceResponseBridge(
        eventBus: bus,
        ttsEngine: _FakeTextToSpeechEngine(),
      );
      final legacyEcosystem = VoiceRealtimeEcosystem(
        eventBus: bus,
        runtimeEngine: legacyRuntime,
        responseBridge: legacyBridge,
        foregroundService: legacyService,
        useStreamFirstAudio: false,
      );

      await legacyEcosystem.start();
      await legacyEcosystem.stop();
      await legacyRuntime.dispose();
      await legacyBridge.dispose();

      expect(legacyService.startCalls, isEmpty);
      expect(legacyService.stopCalls, 0);
    });

    test('falha no startService nao propaga e registra telemetria', () async {
      foregroundService.failStart = true;

      await ecosystem.start();

      expect(runtimeEngine.isStarted, isTrue);
      expect(responseBridge.isStarted, isTrue);
      expect(ecosystem.isStarted, isTrue);
      expect(ecosystem.isForegroundStarted, isFalse);

      final degraded = bus.timeline
          .whereType<VoiceSystemDegradedEvent>()
          .single;
      expect(degraded.source, 'voice_realtime_ecosystem');
      expect(degraded.reason, 'foreground_service_start_failed');
      expect(degraded.correlationId, 'foreground_service');
      expect(degraded.metadata['error'], contains('foreground start failed'));
    });

    test('composicao default de teste usa foreground service stub', () {
      final localEcosystem = VoiceRealtimeEcosystem(
        eventBus: bus,
        runtimeEngine: runtimeEngine,
        responseBridge: responseBridge,
        useStreamFirstAudio: true,
      );

      expect(
        localEcosystem.foregroundService,
        isA<StubVoiceForegroundService>(),
      );
    });

    test('stop limpa contexto ativo de sessao de voz', () async {
      final contextHolder = VoiceSessionContextHolder();
      final localRuntime = VoiceRuntimeEngine(
        eventBus: bus,
        registry: VoiceRuntimeRegistry(eventBus: bus),
        useStreamFirstAudio: false,
      );
      final localBridge = VoiceResponseBridge(
        eventBus: bus,
        ttsEngine: _FakeTextToSpeechEngine(),
      );
      final localEcosystem = VoiceRealtimeEcosystem(
        eventBus: bus,
        runtimeEngine: localRuntime,
        responseBridge: localBridge,
        foregroundService: _FakeVoiceForegroundService(),
        sessionContextHolder: contextHolder,
        useStreamFirstAudio: false,
      );

      await localEcosystem.start();
      localEcosystem.updateActiveContext(
        projectId: '9',
        userId: '7',
        sessionToken: 'active-token',
      );
      expect(contextHolder.currentProjectId, '9');
      expect(contextHolder.currentUserId, '7');
      expect(contextHolder.activeSessionToken, 'active-token');
      expect(localEcosystem.activeSessionToken, 'active-token');

      await localEcosystem.stop();
      await localRuntime.dispose();
      await localBridge.dispose();

      expect(contextHolder.currentProjectId, isNull);
      expect(contextHolder.currentUserId, isNull);
      expect(contextHolder.activeSessionToken, isNull);
      expect(localEcosystem.activeSessionToken, isNull);
    });
  });
}

class _FakeVoiceForegroundService implements VoiceForegroundService {
  final List<_StartForegroundCall> startCalls = [];
  final List<String> updateCalls = [];
  var stopCalls = 0;
  var failStart = false;

  @override
  Future<void> startService({
    required String title,
    required String message,
  }) async {
    startCalls.add(_StartForegroundCall(title: title, message: message));
    if (failStart) {
      throw StateError('foreground start failed');
    }
  }

  @override
  Future<void> updateMessage(String message) async {
    updateCalls.add(message);
  }

  @override
  Future<void> stopService() async {
    stopCalls += 1;
  }
}

class _StartForegroundCall {
  const _StartForegroundCall({required this.title, required this.message});

  final String title;
  final String message;
}

class _FakeTextToSpeechEngine implements TextToSpeechEngine {
  @override
  Future<void> speak(String text, String correlationId) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
