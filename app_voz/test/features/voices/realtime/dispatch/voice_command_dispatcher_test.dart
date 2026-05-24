import 'dart:async';

import 'package:app_voz/features/voices/realtime/dispatch/handlers/metronome_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/playback_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/track_command_handler.dart';
import 'package:app_voz/features/voices/realtime/dispatch/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/realtime/dispatch/voice_command_handler.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCommandDispatcher', () {
    late VoiceRealtimeEventBus bus;
    late _FakeMetronomeService metronomeService;
    late _FakePlaybackService playbackService;
    late _FakeTrackService trackService;
    late VoiceCommandDispatcher dispatcher;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      metronomeService = _FakeMetronomeService();
      playbackService = _FakePlaybackService();
      trackService = _FakeTrackService();
      dispatcher = VoiceCommandDispatcher(
        eventBus: bus,
        handlers: <Type, VoiceCommandHandler<dynamic>>{
          MetronomeIntent: MetronomeCommandHandler(
            service: metronomeService,
            eventBus: bus,
          ),
          PlaybackIntent: PlaybackCommandHandler(
            service: playbackService,
            eventBus: bus,
          ),
          TrackIntent: TrackCommandHandler(
            service: trackService,
            eventBus: bus,
          ),
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

        bus.publish(
          VoiceCommandInterpretedEvent(
            source: 'test',
            correlationId: 'playback-flow',
            intent: const PlaybackIntent(action: 'start', rawText: 'play'),
          ),
        );
        await dispatcher.idle;

        expect(playbackService.actions, ['start']);
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

        expect(trackService.actions, ['record']);
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
  });
}

class _FakeMetronomeService implements MetronomeService {
  final List<int> bpms = [];
  var failNext = false;
  Future<void>? blockNext;

  @override
  Future<void> setBpm(int bpm) async {
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
  Future<void> pause() async {
    actions.add('pause');
  }

  @override
  Future<void> start() async {
    actions.add('start');
  }

  @override
  Future<void> stop() async {
    actions.add('stop');
  }
}

class _FakeTrackService implements TrackService {
  final List<String> actions = [];

  @override
  Future<void> delete() async {
    actions.add('delete');
  }

  @override
  Future<void> mute() async {
    actions.add('mute');
  }

  @override
  Future<void> record() async {
    actions.add('record');
  }
}
