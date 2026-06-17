import 'dart:async';

import 'package:app_voz/features/voices/coordination/voice_diagnostics.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/coordination/voice_state_machine.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_registry.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event.dart';
import 'package:app_voz/features/voices/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VoiceSessionManager manager;

  setUp(() {
    manager = VoiceSessionManager.instance;
    manager.resetForTesting();
  });

  tearDown(() {
    manager.resetForTesting();
  });

  group('VoiceSessionManager', () {
    test('garante ownership exclusivo da escuta STT', () {
      expect(manager.claimListening('home'), isTrue);
      expect(manager.activeOwnerId, 'home');
      expect(manager.audioOwnerType, VoiceAudioOwnerType.stt);
      expect(manager.stateMachine.state, VoiceState.listening);

      expect(manager.claimListening('dashboard'), isFalse);
      expect(manager.activeOwnerId, 'home');
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );

      manager.releaseOwner('home');
      expect(manager.activeOwnerId, isNull);
      expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
    });

    test('modo gravacao bloqueia STT e registra conflito de microfone', () {
      manager.enterRecordingMode(ownerId: 'editor');

      expect(manager.recordingActive, isTrue);
      expect(manager.stateMachine.state, VoiceState.recording);
      expect(manager.claimListening('home'), isFalse);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );

      manager.exitRecordingMode(ownerId: 'editor');
      expect(manager.recordingActive, isFalse);
      expect(manager.claimListening('home'), isTrue);
    });

    test('playback e bloqueado durante gravacao', () async {
      manager.enterRecordingMode(ownerId: 'editor');

      final started = await manager.beginPlayback(ownerId: 'player');

      expect(started, isFalse);
      expect(manager.recordingActive, isTrue);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.microphoneConflict,
      );
    });

    test(
      'publica eventos realtime para listening, recording e playback',
      () async {
        final bus = manager.diagnostics.eventBus;

        expect(manager.claimListening('home'), isTrue);
        manager.releaseOwner('home');
        manager.enterRecordingMode(ownerId: 'editor');
        manager.exitRecordingMode(ownerId: 'editor');
        final playbackStarted = await manager.beginPlayback(ownerId: 'player');
        manager.endPlayback(ownerId: 'player');

        expect(playbackStarted, isTrue);
        expect(
          bus.timeline.map((event) => event.type),
          containsAll([
            VoiceRealtimeEventType.recordingStarted,
            VoiceRealtimeEventType.recordingStopped,
            VoiceRealtimeEventType.playbackStarted,
            VoiceRealtimeEventType.playbackStopped,
            VoiceRealtimeEventType.voiceStateChanged,
          ]),
        );
      },
    );

    test(
      'cancelamento por owner antigo nao derruba sessao ativa nova',
      () async {
        expect(manager.claimListening('home'), isTrue);

        await manager.cancelListening(ownerId: 'dashboard');

        expect(manager.activeOwnerId, 'home');
        expect(manager.audioOwnerType, VoiceAudioOwnerType.stt);
        expect(manager.stateMachine.state, VoiceState.listening);
      },
    );

    test('recovery respeita limite de tentativas e evita loop infinito', () {
      for (var i = 0; i < VoiceSessionManager.maxRecoveryAttempts; i++) {
        manager.stateMachine.incrementRecoveryAttempts();
      }

      var recovered = false;
      manager.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {
          recovered = true;
        },
      );

      expect(recovered, isFalse);
      expect(manager.stateMachine.state, VoiceState.error);
      expect(
        manager.diagnostics.latest?.type,
        VoiceDiagnosticEventType.stateTransition,
      );
      expect(
        manager.diagnostics.events.any(
          (event) => event.type == VoiceDiagnosticEventType.recoverySkipped,
        ),
        isTrue,
      );
    });

    test('notListening sem texto libera owner para proxima escuta', () async {
      final speech = _FakeSpeechService();
      final manager = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(manager.dispose);

      final started = await manager.startListening(
        ownerId: 'home',
        onResult: (_) {},
      );

      expect(started, isTrue);
      expect(manager.activeOwnerId, 'home');

      speech.emitStatus('notListening');

      expect(manager.activeOwnerId, isNull);
      expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
    });

    test('done sem texto libera owner para proxima escuta', () async {
      final speech = _FakeSpeechService();
      final manager = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(manager.dispose);

      final started = await manager.startListening(
        ownerId: 'home',
        onResult: (_) {},
      );

      expect(started, isTrue);
      speech.emitStatus('done');

      expect(manager.activeOwnerId, isNull);
      expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
    });

    test(
      'startListening nao duplica sessao durante start em andamento',
      () async {
        final speech = _FakeSpeechService(startCompleter: Completer<bool>());
        final manager = VoiceSessionManager.forTesting(speechService: speech);
        addTearDown(manager.dispose);

        final firstStart = manager.startListening(
          ownerId: 'home',
          onResult: (_) {},
        );
        await Future<void>.delayed(Duration.zero);

        final secondStart = await manager.startListening(
          ownerId: 'home',
          onResult: (_) {},
        );

        expect(secondStart, isFalse);
        expect(speech.startCalls, 1);
        expect(
          manager.diagnostics.events.any(
            (event) => event.reason == 'start_in_progress',
          ),
          isTrue,
        );

        speech.completeStart(true);
        expect(await firstStart, isTrue);
      },
    );

    test('startListening nao reinicia quando owner ja esta ouvindo', () async {
      final speech = _FakeSpeechService();
      final manager = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(manager.dispose);

      expect(
        await manager.startListening(ownerId: 'home', onResult: (_) {}),
        isTrue,
      );

      expect(
        await manager.startListening(ownerId: 'home', onResult: (_) {}),
        isFalse,
      );
      expect(speech.startCalls, 1);
      expect(
        manager.diagnostics.events.any(
          (event) => event.reason == 'already_listening',
        ),
        isTrue,
      );
    });

    test('error_busy libera owner e aplica cooldown de start', () async {
      final speech = _FakeSpeechService();
      final manager = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(manager.dispose);

      expect(
        await manager.startListening(ownerId: 'home', onResult: (_) {}),
        isTrue,
      );

      speech.emitError('error_busy');

      expect(manager.activeOwnerId, isNull);
      expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
      expect(manager.isBusyCooldownActive, isTrue);
      expect(
        await manager.startListening(ownerId: 'home', onResult: (_) {}),
        isFalse,
      );
      expect(speech.startCalls, 1);
    });

    test('multiplos recoveries nao duplicam tentativa pendente', () {
      final manager = VoiceSessionManager.forTesting(
        speechService: _FakeSpeechService(),
      );
      addTearDown(manager.dispose);

      var recoveries = 0;
      manager.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {
          recoveries++;
        },
      );
      manager.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {
          recoveries++;
        },
      );

      expect(recoveries, 0);
      expect(
        manager.diagnostics.events.any(
          (event) => event.type == VoiceDiagnosticEventType.recoveryScheduled,
        ),
        isTrue,
      );
      expect(
        manager.diagnostics.events.any(
          (event) => event.reason == 'recovery_already_pending',
        ),
        isTrue,
      );
    });

    test(
      'reset manual cancela recovery pendente, libera owner e cooldown',
      () async {
        final speech = _FakeSpeechService();
        final manager = VoiceSessionManager.forTesting(speechService: speech);
        addTearDown(manager.dispose);

        expect(
          await manager.startListening(ownerId: 'home', onResult: (_) {}),
          isTrue,
        );
        speech.emitError('error_busy');
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => true,
          onRecover: () async {},
        );

        expect(manager.isBusyCooldownActive, isTrue);
        expect(manager.hasPendingRecovery, isTrue);

        await manager.forceResetListeningSession(
          ownerId: 'home',
          reason: 'manual_mic_tap',
          clearBusyCooldown: true,
        );

        expect(manager.activeOwnerId, isNull);
        expect(manager.audioOwnerType, VoiceAudioOwnerType.none);
        expect(manager.hasPendingRecovery, isFalse);
        expect(manager.isBusyCooldownActive, isFalse);
        expect(speech.cancelCalls, 1);
      },
    );

    test('resultado final antigo nao executa apos reset manual', () async {
      final speech = _FakeSpeechService();
      final manager = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(manager.dispose);

      var results = 0;
      expect(
        await manager.startListening(
          ownerId: 'home',
          onResult: (_) => results++,
        ),
        isTrue,
      );

      await manager.forceResetListeningSession(
        ownerId: 'home',
        reason: 'manual_mic_tap',
        clearBusyCooldown: true,
      );

      speech.emitResult('projetos');

      expect(results, 0);
      expect(
        manager.diagnostics.events.any(
          (event) => event.reason == 'stale_result',
        ),
        isTrue,
      );
    });

    test(
      'recovery pulado por condition_false libera latch e permite novo recovery',
      () {
        final manager = VoiceSessionManager.forTesting(
          speechService: _FakeSpeechService(),
        );
        addTearDown(manager.dispose);

        // Agendar recovery com condição que sempre falha
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => false,
          onRecover: () async {},
        );

        expect(manager.hasPendingRecovery, isTrue);

        // Engine chama shouldRecover via registry → condition_false
        final session =
            VoiceRuntimeRegistry.instance.activeVoiceSession;
        expect(session, isNotNull);
        final canRecover = session!.shouldRecover();
        expect(canRecover, isFalse);

        // Latch deve ter sido liberado automaticamente
        expect(manager.hasPendingRecovery, isFalse);

        // Deve ser possível agendar novo recovery sem bloqueio
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => true,
          onRecover: () async {},
        );
        expect(manager.hasPendingRecovery, isTrue);
        expect(
          manager.diagnostics.events
              .where((e) => e.reason == 'recovery_already_pending')
              .length,
          0,
        );
      },
    );

    test(
      'recovery executado com sucesso libera latch antes de onRecover',
      () async {
        final manager = VoiceSessionManager.forTesting(
          speechService: _FakeSpeechService(),
        );
        addTearDown(manager.dispose);

        var pendingDuringRecover = true;
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => true,
          onRecover: () async {
            pendingDuringRecover = manager.hasPendingRecovery;
          },
        );

        expect(manager.hasPendingRecovery, isTrue);
        final session =
            VoiceRuntimeRegistry.instance.activeVoiceSession;
        expect(session, isNotNull);
        await session!.recover();

        // Latch deve ter sido limpo antes de onRecover executar
        expect(pendingDuringRecover, isFalse);
        expect(manager.hasPendingRecovery, isFalse);
      },
    );

    test(
      'resultado final chega apos done na mesma geracao e processado',
      () async {
        final speech = _FakeSpeechService();
        final manager = VoiceSessionManager.forTesting(speechService: speech);
        addTearDown(manager.dispose);

        var results = 0;
        await manager.startListening(
          ownerId: 'home',
          onResult: (_) => results++,
        );

        // done chega antes do resultado (ordem Android)
        speech.emitStatus('done');
        expect(manager.activeOwnerId, isNull);

        // Resultado chega depois — mesma geração, deve ser processado
        speech.emitResult('projetos');
        expect(results, 1);
      },
    );

    test(
      'recovery nao inicia enquanto shouldRecover retorna false',
      () async {
        final manager = VoiceSessionManager.forTesting(
          speechService: _FakeSpeechService(),
        );
        addTearDown(manager.dispose);

        var recovered = false;
        // shouldRecover false simula voiceExecutandoComando=true no mixin
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => false,
          onRecover: () async {
            recovered = true;
          },
        );

        final session =
            VoiceRuntimeRegistry.instance.activeVoiceSession;
        expect(session, isNotNull);
        final canRecover = await VoiceRuntimeRegistry.instance.recoverVoiceSession(
          ownerId: 'home',
          token: session!.token,
        );

        expect(canRecover, isFalse);
        expect(recovered, isFalse);
        expect(manager.hasPendingRecovery, isFalse);
      },
    );

    test(
      'error_busy repetido nao cria loop de recovery infinito',
      () async {
        final speech = _FakeSpeechService();
        final manager = VoiceSessionManager.forTesting(speechService: speech);
        addTearDown(manager.dispose);

        await manager.startListening(ownerId: 'home', onResult: (_) {});
        speech.emitError('error_busy');
        expect(manager.isBusyCooldownActive, isTrue);

        // Tentar agendar recovery com cooldown ativo → shouldRecover=false
        manager.scheduleRecovery(
          ownerId: 'home',
          shouldRecover: () => !manager.isBusyCooldownActive,
          onRecover: () async {},
        );

        final session =
            VoiceRuntimeRegistry.instance.activeVoiceSession;
        if (session != null) {
          session.shouldRecover();
        }

        // Latch liberado, sem segundo start
        expect(manager.hasPendingRecovery, isFalse);
        expect(speech.startCalls, 1);
      },
    );
  });

  group('VoiceSessionManager onRouteDidPop H10.1', () {
    test('libera owner STT sincronamente no pop da rota', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      mgr.claimListening('meus_projetos');
      expect(mgr.activeOwnerId, 'meus_projetos');
      expect(mgr.audioOwnerType, VoiceAudioOwnerType.stt);

      mgr.onRouteDidPop();

      expect(mgr.activeOwnerId, isNull);
      expect(mgr.audioOwnerType, VoiceAudioOwnerType.none);
    });

    test('tela anterior pode reivindicar ownership imediatamente apos pop', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      mgr.claimListening('meus_projetos');

      mgr.onRouteDidPop();

      expect(mgr.claimListening('home'), isTrue);
      expect(mgr.activeOwnerId, 'home');
    });

    test('cancela recovery pendente da rota descartada', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      mgr.claimListening('meus_projetos');
      mgr.scheduleRecovery(
        ownerId: 'meus_projetos',
        shouldRecover: () => true,
        onRecover: () async {},
      );
      expect(mgr.hasPendingRecovery, isTrue);

      mgr.onRouteDidPop();

      expect(mgr.hasPendingRecovery, isFalse);
      expect(mgr.activeOwnerId, isNull);
    });

    test('sem owner STT ativo apenas invalida recovery', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      mgr.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {},
      );
      expect(mgr.hasPendingRecovery, isTrue);

      mgr.onRouteDidPop();

      expect(mgr.hasPendingRecovery, isFalse);
      expect(mgr.activeOwnerId, isNull);
    });

    test('nao afeta modo gravacao ativo', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      mgr.enterRecordingMode(ownerId: 'editor');
      expect(mgr.recordingActive, isTrue);

      mgr.onRouteDidPop();

      expect(mgr.recordingActive, isTrue);
      expect(mgr.audioOwnerType, VoiceAudioOwnerType.recorder);
    });

    test('recovery antigo nao bloqueia owner atual apos pop', () {
      final speech = _FakeSpeechService();
      final mgr = VoiceSessionManager.forTesting(speechService: speech);
      addTearDown(mgr.dispose);

      // Tela filha (meus_projetos) tinha recovery pendente
      mgr.claimListening('meus_projetos');
      mgr.scheduleRecovery(
        ownerId: 'meus_projetos',
        shouldRecover: () => true,
        onRecover: () async {},
      );

      // Pop: libera owner e cancela recovery antigo
      mgr.onRouteDidPop();

      expect(mgr.hasPendingRecovery, isFalse);

      // Home agora pode agendar seu proprio recovery sem bloqueio
      mgr.claimListening('home');
      mgr.scheduleRecovery(
        ownerId: 'home',
        shouldRecover: () => true,
        onRecover: () async {},
      );
      expect(mgr.hasPendingRecovery, isTrue);
      expect(
        mgr.diagnostics.events
            .where((e) => e.reason == 'recovery_already_pending')
            .length,
        0,
      );
    });
  });
}


class _FakeSpeechService implements SpeechService {
  _FakeSpeechService({Completer<bool>? startCompleter})
    : _startCompleter = startCompleter;

  final Completer<bool>? _startCompleter;
  void Function(String status)? _onStatus;
  void Function(String error)? _onError;
  void Function(String text)? _onResult;
  var startCalls = 0;
  var cancelCalls = 0;
  var _listening = false;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    return true;
  }

  @override
  Future<bool> startListening({
    required Function(String text) onResult,
    Function(String status)? onStatus,
    Function(String error)? onError,
  }) async {
    startCalls++;
    _onResult = onResult;
    _onStatus = onStatus;
    _onError = onError;
    final result = _startCompleter == null
        ? true
        : await _startCompleter.future;
    _listening = result;
    return result;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
  }

  @override
  Future<void> cancelListening() async {
    cancelCalls++;
    _listening = false;
  }

  void completeStart(bool result) {
    _startCompleter?.complete(result);
  }

  void emitStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _listening = false;
    }
    _onStatus?.call(status);
  }

  void emitError(String error) {
    _listening = false;
    _onError?.call(error);
  }

  void emitResult(String text) {
    _onResult?.call(text);
  }
}
