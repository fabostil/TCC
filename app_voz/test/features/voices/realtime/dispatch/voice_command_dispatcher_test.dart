import 'dart:async';

import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contratos/audio_output_guard.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contracts/voice_recording_context_resolver.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/metronome_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/playback_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/recording_management_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/track_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/realtime/dispatch/voice_command_handler.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/observability/runtime_telemetry_tracer.dart';
import 'package:app_voz/features/voices/realtime/tts/intent_response_formatter.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCommandDispatcher', () {
    late VoiceRealtimeEventBus bus;
    late _FakeMetronomeService metronomeService;
    late _FakePlaybackService playbackService;
    late _FakeAudioOutputGuard audioOutputGuard;
    late _FakeTrackService trackService;
    late _FakeRecordingManagementService recordingService;
    late RecordingManagementCommandHandler recordingManagementHandler;
    late VoiceCommandDispatcher dispatcher;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      metronomeService = _FakeMetronomeService();
      playbackService = _FakePlaybackService();
      audioOutputGuard = _FakeAudioOutputGuard();
      trackService = _FakeTrackService();
      recordingService = _FakeRecordingManagementService();
      recordingManagementHandler = RecordingManagementCommandHandler(
        recordingService: recordingService,
        recordingContextResolver: _FakeVoiceRecordingContextResolver(
          recordingService.recordings.first,
        ),
        eventBus: bus,
      );
      dispatcher = VoiceCommandDispatcher(
        eventBus: bus,
        pendingTransactionTimeout: const Duration(seconds: 5),
        handlers: <Type, VoiceCommandHandler<dynamic>>{
          MetronomeIntent: MetronomeCommandHandler(
            service: metronomeService,
            eventBus: bus,
          ),
          PlaybackIntent: PlaybackCommandHandler(
            service: playbackService,
            audioOutputGuard: audioOutputGuard,
            eventBus: bus,
          ),
          TrackIntent: TrackCommandHandler(
            service: trackService,
            eventBus: bus,
          ),
          DeleteLastRecordingIntent: recordingManagementHandler,
        },
      )..start();
    });

    tearDown(() async {
      await dispatcher.dispose();
    });

    test('roteia MetronomeIntent para o handler correto', () async {
      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'metronome-flow',
          intent: const MetronomeIntent(bpm: 120, rawText: 'metronomo 120'),
        ),
      );
      await dispatcher.idle;

      expect(metronomeService.bpms, [120]);
      expect(playbackService.actions, isEmpty);
      expect(trackService.actions, isEmpty);

      final handlerEvent = bus.timeline
          .whereType<VoiceStateChangedEvent>()
          .where((event) => event.reason == 'metronome_bpm_set')
          .single;
      expect(handlerEvent.correlationId, 'metronome-flow');
      expect(handlerEvent.metadata['bpm'], 120);
    });

    test('PlaybackCommandHandler aciona play, pause e stop reais', () async {
      playbackService.currentPath = 'track.m4a';
      for (final action in ['start', 'pause', 'stop']) {
        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'playback-$action',
            intent: PlaybackIntent(action: action, rawText: action),
          ),
        );
      }
      await dispatcher.idle;

      expect(playbackService.actions, ['play', 'pause', 'stop']);
      final handled = bus.timeline
          .whereType<VoiceStateChangedEvent>()
          .where((event) => event.reason == 'playback_command_dispatched')
          .toList();
      expect(handled.map((event) => event.metadata['action']), [
        'start',
        'pause',
        'stop',
      ]);
    });

    test(
      'PlaybackCommandHandler rejeita start sem gravacao selecionada',
      () async {
        playbackService.currentPath = null;

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'empty-path-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await dispatcher.idle;

        expect(playbackService.actions, isEmpty);
        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.reason, 'no_track_selected');
        expect(failed.correlationId, 'empty-path-flow');
        expect(failed.intent, isA<PlaybackIntent>());

        final formatter = IntentResponseFormatter();
        expect(
          formatter.formatFailure('no_track_selected'),
          'Nenhuma gravação foi selecionada no editor para reproduzir.',
        );
      },
    );

    test(
      'PlaybackCommandHandler rejeita start quando canal de audio esta ocupado',
      () async {
        final tracer = RuntimeTelemetryTracer(eventBus: bus);
        playbackService.currentPath = 'track.m4a';
        audioOutputGuard.available = false;

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'audio-busy-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await dispatcher.idle;

        expect(playbackService.actions, isEmpty);
        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.reason, 'audio_output_unavailable');
        expect(failed.correlationId, 'audio-busy-flow');
        expect(failed.intent, isA<PlaybackIntent>());

        final trace = tracer.getTraceChain('audio-busy-flow');
        expect(
          trace.whereType<VoiceStateChangedEvent>().where(
            (event) => event.reason == 'audio_output_unavailable',
          ),
          isNotEmpty,
        );
        expect(trace.whereType<VoiceCommandFailedEvent>(), isNotEmpty);

        await tracer.dispose();
      },
    );

    test('TrackCommandHandler aciona record e mute no dominio real', () async {
      for (final action in ['record', 'mute']) {
        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'track-$action',
            intent: TrackIntent(action: action, rawText: action),
          ),
        );
      }
      await dispatcher.idle;

      expect(trackService.actions, [
        'startRecordingTrack',
        'muteSelectedTrack',
      ]);
      final handled = bus.timeline
          .whereType<VoiceStateChangedEvent>()
          .where((event) => event.reason == 'track_command_dispatched')
          .toList();
      expect(handled.map((event) => event.correlationId), [
        'track-record',
        'track-mute',
      ]);
    });

    test('ignora comandos duplicados pelo mesmo correlationId', () async {
      final event = VoiceCommandInterpretedEvent(
        source: 'test',
        correlationId: 'duplicate-flow',
        intent: const MetronomeIntent(bpm: 128, rawText: 'metronomo 128'),
      );

      bus.publish(event);
      bus.publish(event);
      await dispatcher.idle;

      expect(metronomeService.bpms, [128]);
      final duplicate = bus.timeline
          .whereType<VoiceStateChangedEvent>()
          .where((event) => event.reason == 'duplicate_command_ignored')
          .single;
      expect(duplicate.correlationId, 'duplicate-flow');
    });

    test(
      'absorve falha de handler e continua operacional para comandos futuros',
      () async {
        metronomeService.failNext = true;

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'failing-flow',
            intent: const MetronomeIntent(bpm: 140, rawText: 'metronomo 140'),
          ),
        );
        await dispatcher.idle;

        final degraded = bus.timeline
            .whereType<VoiceSystemDegradedEvent>()
            .single;
        expect(degraded.source, 'voice_command_dispatcher');
        expect(degraded.reason, 'command_handler_failed');
        expect(degraded.correlationId, 'failing-flow');

        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.source, 'metronome_command_handler');
        expect(failed.reason, 'metronome_update_failed');
        expect(failed.correlationId, 'failing-flow');
        expect(failed.intent, isA<MetronomeIntent>());
        expect(failed.metadata['bpm'], 140);

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'playback-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await dispatcher.idle;

        playbackService.currentPath = 'track.m4a';
        expect(playbackService.actions, ['play']);
      },
    );

    test(
      'ignora UnknownIntent sem executar handlers e mantem barramento vivo',
      () async {
        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'unknown-flow',
            intent: const UnknownIntent('comando aleatorio'),
          ),
        );
        await dispatcher.idle;

        expect(metronomeService.bpms, isEmpty);
        expect(playbackService.actions, isEmpty);
        expect(trackService.actions, isEmpty);

        final ignored = bus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where((event) => event.reason == 'unknown_intent_ignored')
            .single;
        expect(ignored.correlationId, 'unknown-flow');

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'track-flow',
            intent: const TrackIntent(action: 'record', rawText: 'gravar'),
          ),
        );
        await dispatcher.idle;

        expect(trackService.actions, ['startRecordingTrack']);
      },
    );

    test('executa comandos de forma serializada', () async {
      final firstCanFinish = Completer<void>();
      metronomeService.blockNext = firstCanFinish.future;

      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'first-flow',
          intent: const MetronomeIntent(bpm: 90, rawText: 'metronomo 90'),
        ),
      );
      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'second-flow',
          intent: const PlaybackIntent(action: 'pause', rawText: 'pause'),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(playbackService.actions, isEmpty);

      firstCanFinish.complete();
      await dispatcher.idle;

      expect(metronomeService.bpms, [90]);
      expect(playbackService.actions, ['pause']);
    });

    test(
      'confirma transacao pendente preservando correlationId original',
      () async {
        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'delete-flow',
            intent: const DeleteLastRecordingIntent(
              rawText: 'deletar ultima gravacao',
            ),
          ),
        );
        await dispatcher.idle;

        expect(recordingService.deleteCalls, isEmpty);
        expect(
          bus.timeline
              .whereType<VoiceCommandConfirmationRequiredEvent>()
              .single
              .correlationId,
          'delete-flow',
        );

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'confirm-flow',
            intent: const ConfirmIntent(rawText: 'confirmar'),
          ),
        );
        await dispatcher.idle;

        expect(recordingService.deleteCalls.map((recording) => recording.id), [
          1,
        ]);
        final resolved = bus.timeline
            .whereType<VoiceCommandConfirmationResolvedEvent>()
            .single;
        expect(resolved.approved, isTrue);
        expect(resolved.correlationId, 'delete-flow');
        final dispatched = bus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where((event) => event.reason == 'pending_transaction_confirmed')
            .single;
        expect(dispatched.correlationId, 'delete-flow');
        expect(dispatched.metadata['verdictCorrelationId'], 'confirm-flow');
      },
    );

    test('cancelamento limpa transacao sem excluir gravacao', () async {
      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'delete-cancel-flow',
          intent: const DeleteLastRecordingIntent(
            rawText: 'deletar ultima gravacao',
          ),
        ),
      );
      await dispatcher.idle;

      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'cancel-flow',
          intent: const CancelIntent(rawText: 'cancelar'),
        ),
      );
      await dispatcher.idle;

      expect(recordingService.deleteCalls, isEmpty);
      final resolved = bus.timeline
          .whereType<VoiceCommandConfirmationResolvedEvent>()
          .single;
      expect(resolved.approved, isFalse);
      expect(resolved.correlationId, 'delete-cancel-flow');
      expect(
        const IntentResponseFormatter().formatConfirmationResolved(
          resolved.action,
          resolved.intent,
          approved: resolved.approved,
        ),
        'ExclusÃ£o cancelada. A gravaÃ§Ã£o foi mantida.',
      );
    });

    test('confirmacao orfa e ignorada sem executar acao destrutiva', () async {
      bus.publish(
        VoiceCommandInterpretedEvent(
          source: 'test',
          correlationId: 'orphan-confirm-flow',
          intent: const ConfirmIntent(rawText: 'sim'),
        ),
      );
      await dispatcher.idle;

      expect(recordingService.deleteCalls, isEmpty);
      final ignored = bus.timeline
          .whereType<VoiceStateChangedEvent>()
          .where((event) => event.reason == 'orphan_confirmation_ignored')
          .single;
      expect(ignored.correlationId, 'orphan-confirm-flow');
    });

    test(
      'transacao pendente expira e nao permite confirmacao tardia',
      () async {
        await dispatcher.dispose();
        bus = VoiceRealtimeEventBus();
        recordingService = _FakeRecordingManagementService();
        recordingManagementHandler = RecordingManagementCommandHandler(
          recordingService: recordingService,
          recordingContextResolver: _FakeVoiceRecordingContextResolver(
            recordingService.recordings.first,
          ),
          eventBus: bus,
        );
        dispatcher = VoiceCommandDispatcher(
          eventBus: bus,
          pendingTransactionTimeout: const Duration(milliseconds: 1),
          handlers: <Type, VoiceCommandHandler<dynamic>>{
            DeleteLastRecordingIntent: recordingManagementHandler,
          },
        )..start();

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'timeout-delete-flow',
            intent: const DeleteLastRecordingIntent(
              rawText: 'deletar ultima gravacao',
            ),
          ),
        );
        await dispatcher.idle;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final timeout = bus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where((event) => event.reason == 'pending_transaction_timeout')
            .single;
        expect(timeout.correlationId, 'timeout-delete-flow');

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'late-confirm-flow',
            intent: const ConfirmIntent(rawText: 'confirmar'),
          ),
        );
        await dispatcher.idle;

        expect(recordingService.deleteCalls, isEmpty);
        final ignored = bus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where((event) => event.reason == 'orphan_confirmation_ignored')
            .single;
        expect(ignored.correlationId, 'late-confirm-flow');
      },
    );
  });
}

class _FakeMetronomeService implements MetronomeService {
  final List<int> bpms = [];
  var failNext = false;
  Future<void>? blockNext;

  @override
  Future<void> updateBpm(int bpm) async {
    final blocker = blockNext;
    blockNext = null;
    if (blocker != null) {
      await blocker;
    }
    if (failNext) {
      failNext = false;
      throw StateError('metronome unavailable');
    }
    bpms.add(bpm);
  }
}

class _FakePlaybackService implements PlaybackService {
  final List<String> actions = [];

  @override
  String? currentPath = 'track.m4a';

  @override
  Future<void> pause() async {
    actions.add('pause');
  }

  @override
  Future<void> play() async {
    actions.add('play');
  }

  @override
  Future<void> stop() async {
    actions.add('stop');
  }
}

class _FakeAudioOutputGuard implements AudioOutputGuard {
  var available = true;

  @override
  bool isAudioOutputAvailable() => available;
}

class _FakeTrackService implements TrackService {
  final List<String> actions = [];

  @override
  Future<void> deleteSelectedTrack() async {
    actions.add('deleteSelectedTrack');
  }

  @override
  Future<void> muteSelectedTrack() async {
    actions.add('muteSelectedTrack');
  }

  @override
  Future<void> startRecordingTrack() async {
    actions.add('startRecordingTrack');
  }
}

class _FakeVoiceRecordingContextResolver
    implements VoiceRecordingContextResolver {
  _FakeVoiceRecordingContextResolver(this.recording);

  final Gravacao? recording;

  @override
  Future<Gravacao?> resolveLastRecording() async => recording;
}

class _FakeRecordingManagementService extends RecordingManagementService {
  final recordings = [
    Gravacao(
      id: 1,
      usuarioId: 7,
      nome: 'Take recente',
      caminhoArquivo: 'recente.m4a',
      dataCriacao: DateTime(2026, 5, 24, 10).toIso8601String(),
    ),
  ];
  final List<Gravacao> deleteCalls = [];

  @override
  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    return recordings
        .where((recording) => recording.usuarioId == usuarioId)
        .toList();
  }

  @override
  Future<void> deleteRecording(Gravacao gravacao) async {
    deleteCalls.add(gravacao);
  }
}
