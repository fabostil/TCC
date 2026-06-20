import 'dart:async';
import 'dart:typed_data';

import 'package:app_voz/features/editor/controllers/recording_realtime_coordinator.dart';
import 'package:app_voz/features/editor/services/audio_recording_capture.dart';
import 'package:app_voz/features/editor/services/audio_player_service.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingRealtimeCoordinator', () {
    setUp(() {
      VoiceSessionManager.instance.resetForTesting();
    });

    tearDown(() {
      VoiceSessionManager.instance.resetForTesting();
    });

    test('usa path retornado pelo stop como fonte da verdade', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.wav',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
      );
      String? finalizedPath;

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              finalizedPath = path;
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(coordinator.state.currentPath, '/tmp/take.m4a');

      final saved = await coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              finalizedPath = path;
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(finalizedPath, '/tmp/take.wav');
      expect(saved?.caminhoArquivo, '/tmp/take.wav');
      expect(coordinator.state.currentPath, isNull);
      expect(recordingService.stopCalls, 1);

      coordinator.dispose();
    });

    test('progresso de gravacao incrementa e reseta ao parar', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final playerService = _FakeAudioPlayerService();
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        playerService: playerService,
        automaticSilenceStop: false,
      );

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(coordinator.state.timelineProgress, greaterThan(0));
      expect(coordinator.state.timelineProgress, lessThanOrEqualTo(1));

      await coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(coordinator.state.timelineProgress, 0.0);

      coordinator.dispose();
      await playerService.dispose();
    });

    test(
      'progresso de playback usa posicao e duracao com clamp seguro',
      () async {
        final recordingService = _FakeAudioRecordingCapture(
          startPath: '/tmp/take.m4a',
          stopPath: '/tmp/take.m4a',
        );
        final playerService = _FakeAudioPlayerService();
        final coordinator = RecordingRealtimeCoordinator(
          recordingService: recordingService,
          playerService: playerService,
          automaticSilenceStop: false,
        );

        await coordinator.play(
          path: '/tmp/take.m4a',
          name: 'Take',
          emptyPathMessage: 'vazio',
          recordingActiveMessage: 'gravando',
          onHistory: () {},
        );

        playerService.emitDuration(const Duration(seconds: 10));
        playerService.emitPosition(const Duration(seconds: 4));
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.state.timelineProgress, 0.4);

        playerService.emitPosition(const Duration(seconds: 30));
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.state.timelineProgress, 1.0);

        await coordinator.stopPlayback();

        expect(coordinator.state.timelineProgress, 0.0);

        coordinator.dispose();
        await playerService.dispose();
      },
    );

    test(
      'progresso de playback usa fallback quando duracao e desconhecida',
      () async {
        final recordingService = _FakeAudioRecordingCapture(
          startPath: '/tmp/take.m4a',
          stopPath: '/tmp/take.m4a',
        );
        final playerService = _FakeAudioPlayerService();
        final coordinator = RecordingRealtimeCoordinator(
          recordingService: recordingService,
          playerService: playerService,
          automaticSilenceStop: false,
        );

        await coordinator.play(
          path: '/tmp/take.m4a',
          name: 'Take',
          emptyPathMessage: 'vazio',
          recordingActiveMessage: 'gravando',
          onHistory: () {},
        );

        playerService.emitDuration(null);
        playerService.emitPosition(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.state.timelineProgress, 0.1);

        coordinator.dispose();
        await playerService.dispose();
      },
    );

    test('playback concluido reseta estado de reproducao', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final playerService = _FakeAudioPlayerService();
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        playerService: playerService,
        automaticSilenceStop: false,
      );

      await coordinator.play(
        path: '/tmp/take.m4a',
        name: 'Take',
        emptyPathMessage: 'vazio',
        recordingActiveMessage: 'gravando',
        onHistory: () {},
      );

      expect(coordinator.state.playing, isTrue);

      playerService.emitCompleted();
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.state.playing, isFalse);
      expect(coordinator.state.timelineProgress, 0.0);
      expect(coordinator.state.statusMessage, 'Reprodução finalizada.');

      coordinator.dispose();
      await playerService.dispose();
    });

    test('nao reproduz audio durante gravacao ativa', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final playerService = _FakeAudioPlayerService();
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        playerService: playerService,
        automaticSilenceStop: false,
      );
      var historyCalls = 0;

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              return Gravacao(
                id: 1,
                usuarioId: 1,
                nome: 'Take',
                caminhoArquivo: path,
                dataCriacao: startedAt.toIso8601String(),
              );
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      await coordinator.play(
        path: '/tmp/take.m4a',
        name: 'Take',
        emptyPathMessage: 'vazio',
        recordingActiveMessage: 'Pare a gravacao antes de reproduzir audio.',
        onHistory: () => historyCalls += 1,
      );

      expect(coordinator.state.recording, isTrue);
      expect(coordinator.state.playing, isFalse);
      expect(playerService.playing, isFalse);
      expect(historyCalls, 0);
      expect(
        coordinator.state.statusMessage,
        'Pare a gravacao antes de reproduzir audio.',
      );

      coordinator.dispose();
      await playerService.dispose();
    });

    test(
      'nao inicia captura quando permissao foi revogada antes de gravar',
      () async {
        final recordingService = _FakeAudioRecordingCapture(
          startPath: '/tmp/take.m4a',
          stopPath: '/tmp/take.m4a',
        )..permission = false;
        final coordinator = RecordingRealtimeCoordinator(
          recordingService: recordingService,
          automaticSilenceStop: false,
          observeLifecycle: false,
        );

        await coordinator.startRecording(
          finalizeRecording:
              ({required path, required startedAt, required automatic}) async {
                throw StateError('nao deve finalizar');
              },
          onHistory: (_, _, {recordingId, projectId}) {},
        );

        expect(recordingService.startCalls, 0);
        expect(coordinator.state.recording, isFalse);
        expect(coordinator.state.statusMessage, contains('microfone removida'));
        expect(
          VoiceSessionManager.instance.diagnostics.eventBus.timeline
              .whereType<VoiceCommandFailedEvent>()
              .where(
                (event) =>
                    event.reason ==
                    'microphone_permission_denied_before_recording',
              ),
          isNotEmpty,
        );

        coordinator.dispose();
      },
    );

    test(
      'paused por lifecycle fecha captura e preserva arquivo parcial',
      () async {
        final recordingService = _FakeAudioRecordingCapture(
          startPath: '/tmp/take.m4a',
          stopPath: '/tmp/take-safe.m4a',
        );
        final coordinator = RecordingRealtimeCoordinator(
          recordingService: recordingService,
          automaticSilenceStop: false,
          observeLifecycle: false,
        );

        await coordinator.startRecording(
          finalizeRecording:
              ({required path, required startedAt, required automatic}) async {
                return Gravacao(
                  id: 1,
                  usuarioId: 1,
                  nome: 'Take',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                );
              },
          onHistory: (_, _, {recordingId, projectId}) {},
        );

        await coordinator.handleLifecycleStateForTesting(
          AppLifecycleState.paused,
        );

        expect(recordingService.stopCalls, 1);
        expect(coordinator.pausedByLifecycle, isTrue);
        expect(coordinator.wasRecordingBeforeLifecyclePause, isTrue);
        expect(coordinator.state.recording, isTrue);
        expect(coordinator.state.paused, isTrue);
        expect(coordinator.state.currentPath, '/tmp/take-safe.m4a');
        expect(coordinator.state.statusMessage, contains('interrupção'));

        final saved = await coordinator.stopRecording(
          finalizeRecording:
              ({required path, required startedAt, required automatic}) async {
                return Gravacao(
                  id: 7,
                  usuarioId: 1,
                  nome: 'Take seguro',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                );
              },
          onHistory: (_, _, {recordingId, projectId}) {},
        );

        expect(saved?.caminhoArquivo, '/tmp/take-safe.m4a');
        expect(recordingService.stopCalls, 1);

        coordinator.dispose();
      },
    );

    test('hidden usa o mesmo caminho seguro de paused', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take-hidden.m4a',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
        observeLifecycle: false,
        realtimeShutdown: (_) async {},
      );

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              throw StateError('nao deve finalizar durante hidden');
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      await coordinator.handleLifecycleStateForTesting(
        AppLifecycleState.hidden,
      );

      expect(recordingService.stopCalls, 1);
      expect(coordinator.pausedByLifecycle, isTrue);
      expect(coordinator.state.currentPath, '/tmp/take-hidden.m4a');

      coordinator.dispose();
    });

    test('resumed apos pause por lifecycle exige acao do usuario', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take-safe.m4a',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
        observeLifecycle: false,
        realtimeShutdown: (_) async {},
      );

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async {
              throw StateError('nao deve finalizar durante lifecycle');
            },
        onHistory: (_, _, {recordingId, projectId}) {},
      );
      await coordinator.handleLifecycleStateForTesting(
        AppLifecycleState.inactive,
      );
      await coordinator.handleLifecycleStateForTesting(
        AppLifecycleState.resumed,
      );

      expect(coordinator.state.statusMessage, contains('próxima ação'));
      expect(
        VoiceSessionManager.instance.diagnostics.eventBus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where(
              (event) =>
                  event.reason == 'recording_resume_requires_user_action',
            ),
        isNotEmpty,
      );

      coordinator.dispose();
    });

    test('dispose e idempotente apos detached lifecycle', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
        observeLifecycle: false,
        realtimeShutdown: (_) async {},
      );

      await coordinator.handleLifecycleStateForTesting(
        AppLifecycleState.detached,
      );
      coordinator.dispose();
      coordinator.dispose();

      expect(recordingService.disposeCalls, 1);
    });

    test('PROBLEMA 7: segunda chamada concorrente a stopRecording e ignorada', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
        observeLifecycle: false,
        realtimeShutdown: (_) async {},
      );

      await coordinator.startRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async =>
                Gravacao(
                  id: 1,
                  usuarioId: 1,
                  nome: 'Take',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                ),
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      // Simulate two concurrent stop calls (e.g. voice command + button tap)
      final first = coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async =>
                Gravacao(
                  id: 1,
                  usuarioId: 1,
                  nome: 'Take',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                ),
        onHistory: (_, _, {recordingId, projectId}) {},
      );
      final second = coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async =>
                Gravacao(
                  id: 1,
                  usuarioId: 1,
                  nome: 'Take',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                ),
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      await Future.wait([first, second]);

      // Only one actual stop should have been forwarded to the recorder
      expect(recordingService.stopCalls, 1);

      coordinator.dispose();
    });

    test('PROBLEMA 7: stopRecording quando nao ha gravacao retorna null', () async {
      final recordingService = _FakeAudioRecordingCapture(
        startPath: '/tmp/take.m4a',
        stopPath: '/tmp/take.m4a',
      );
      final coordinator = RecordingRealtimeCoordinator(
        recordingService: recordingService,
        automaticSilenceStop: false,
        observeLifecycle: false,
        realtimeShutdown: (_) async {},
      );

      // Not recording — stop should be a no-op
      final result = await coordinator.stopRecording(
        finalizeRecording:
            ({required path, required startedAt, required automatic}) async =>
                Gravacao(
                  id: 1,
                  usuarioId: 1,
                  nome: 'Take',
                  caminhoArquivo: path,
                  dataCriacao: startedAt.toIso8601String(),
                ),
        onHistory: (_, _, {recordingId, projectId}) {},
      );

      expect(result, isNull);
      expect(recordingService.stopCalls, 0);

      coordinator.dispose();
    });
  });
}

class _FakeAudioRecordingCapture implements AudioRecordingCapture {
  _FakeAudioRecordingCapture({required this.startPath, required this.stopPath});

  final String startPath;
  final String stopPath;
  final StreamController<Uint8List> _chunks =
      StreamController<Uint8List>.broadcast(sync: true);

  int stopCalls = 0;
  int startCalls = 0;
  int disposeCalls = 0;
  bool recording = false;
  bool paused = false;
  bool permission = true;

  @override
  Stream<Uint8List> get rawAudioChunks => _chunks.stream;

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (!_chunks.isClosed) {
      await _chunks.close();
    }
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: -24, max: -12);
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> isPaused() async => paused;

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<void> pauseRecording() async {
    paused = true;
  }

  @override
  Future<void> resumeRecording() async {
    paused = false;
  }

  @override
  Future<String> startRecording() async {
    startCalls += 1;
    recording = true;
    return startPath;
  }

  @override
  Future<String?> stopRecording() async {
    stopCalls += 1;
    recording = false;
    return stopPath;
  }
}

class _FakeAudioPlayerService extends AudioPlayerService {
  _FakeAudioPlayerService() : super();

  final StreamController<PlayerState> _playerStates =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durations =
      StreamController<Duration?>.broadcast(sync: true);

  bool playing = false;
  bool disposed = false;
  String? path = '/tmp/take.m4a';

  @override
  bool get isPlaying => playing;

  @override
  String? get currentPath => path;

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Future<void> play(String path) async {
    this.path = path;
    playing = true;
    _playerStates.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    playing = false;
    _playerStates.add(PlayerState(false, ProcessingState.idle));
  }

  void emitPosition(Duration position) {
    _positions.add(position);
  }

  void emitDuration(Duration? duration) {
    _durations.add(duration);
  }

  void emitCompleted() {
    playing = false;
    _playerStates.add(PlayerState(false, ProcessingState.completed));
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    await _playerStates.close();
    await _positions.close();
    await _durations.close();
    await super.dispose();
  }
}
