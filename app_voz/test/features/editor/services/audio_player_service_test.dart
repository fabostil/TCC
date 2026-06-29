import 'dart:async';
import 'dart:io';

import 'package:app_voz/features/editor/services/audio_player_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('AudioPlayerService', () {
    late Directory tempDir;
    late File audioFile;
    late _FakeAudioPlayerClient player;
    late _FakeAudioPlaybackSessionClient session;
    late AudioPlayerService service;
    var serviceDisposed = false;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_player_service_test_',
      );
      audioFile = File('${tempDir.path}/take.m4a');
      await audioFile.writeAsBytes(const [0, 1, 2, 3]);
      player = _FakeAudioPlayerClient();
      session = _FakeAudioPlaybackSessionClient();
      service = AudioPlayerService.test(player: player, sessionClient: session);
      serviceDisposed = false;
    });

    tearDown(() async {
      if (!serviceDisposed) {
        await service.dispose();
      }
      await player.closeStreams();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'play prepara arquivo novo, inicia playback e atualiza currentPath',
      () async {
        await service.play(audioFile.path);

        expect(service.currentPath, audioFile.path);
        expect(player.calls, [
          'stop',
          'setLoopModeOff',
          'setFilePath:${audioFile.path}',
          'play',
        ]);
        expect(session.calls, ['begin:audio_player_play']);
        expect(player.playing, isTrue);
      },
    );

    test(
      'play com mesmo path ja tocando nao prepara player novamente',
      () async {
        await service.play(audioFile.path);
        player.calls.clear();
        session.calls.clear();

        await service.play(audioFile.path);

        expect(player.calls, isEmpty);
        expect(session.calls, isEmpty);
      },
    );

    test(
      'conclusao natural reseta estado e posiciona arquivo no inicio',
      () async {
        await service.play(audioFile.path);
        player.calls.clear();
        session.calls.clear();

        player.emitCompleted();
        await pumpEventQueue();

        expect(player.playing, isFalse);
        expect(player.calls, ['stop', 'seek:0']);
        expect(session.calls, ['end:playback_completed']);
      },
    );

    test(
      'completed duplicado nao executa cleanup nem encerra sessao de novo',
      () async {
        await service.play(audioFile.path);
        player.calls.clear();
        session.calls.clear();
        player.blockStop = true;

        player.emitCompleted();
        player.emitCompleted();
        await pumpEventQueue();

        expect(player.calls, ['stop']);
        expect(session.calls, ['end:playback_completed']);

        player.completeBlockedStop();
        await pumpEventQueue();
      },
    );

    test(
      'mesmo arquivo pode tocar novamente depois da conclusao natural',
      () async {
        await service.play(audioFile.path);
        player.emitCompleted();
        await pumpEventQueue();
        player.calls.clear();
        session.calls.clear();

        await service.play(audioFile.path);

        // setLoopModeOff is always called before play to prevent infinite loop
        expect(player.calls, ['setLoopModeOff', 'play']);
        expect(session.calls, ['begin:audio_player_play']);
        expect(player.playing, isTrue);
        expect(service.currentPath, audioFile.path);
      },
    );

    test(
      'mesmo arquivo nao entra em loop infinito ao tocar novamente',
      () async {
        // Play → complete → play again: loop mode must be off each time
        await service.play(audioFile.path);
        player.emitCompleted();
        await pumpEventQueue();
        player.calls.clear();

        await service.play(audioFile.path);

        expect(player.calls, contains('setLoopModeOff'));
      },
    );

    test('play rejeita path vazio antes de reservar playback', () async {
      await expectLater(
        service.play(''),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Caminho do audio vazio.'),
          ),
        ),
      );
      expect(session.calls, isEmpty);
      expect(player.calls, isEmpty);
    });

    test('play rejeita arquivo inexistente e limpa currentPath', () async {
      await service.play(audioFile.path);
      final missingPath = '${tempDir.path}/missing.m4a';

      await expectLater(
        service.play(missingPath),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Arquivo de audio nao encontrado.'),
          ),
        ),
      );

      expect(service.currentPath, isNull);
    });

    test('play rejeita quando sessao de audio esta indisponivel', () async {
      session.beginResult = false;

      await expectLater(
        service.play(audioFile.path),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Áudio indisponível'),
          ),
        ),
      );
      expect(player.calls, isEmpty);
    });

    test(
      'play registra falha e libera sessao quando setFilePath falha',
      () async {
        final error = StateError('set path failed');
        player.setFilePathError = error;

        await expectLater(service.play(audioFile.path), throwsA(same(error)));
        expect(session.startFailures, hasLength(1));
        expect(session.calls, [
          'begin:audio_player_play',
          'failure:audio_player_start_failed',
          'end:play_failed',
        ]);
        expect(player.playing, isFalse);
      },
    );

    test('play registra falha e libera sessao quando play falha', () async {
      final error = StateError('play failed');
      player.playError = error;

      await expectLater(service.play(audioFile.path), throwsA(same(error)));
      expect(session.startFailures, hasLength(1));
      expect(session.calls, [
        'begin:audio_player_play',
        'failure:audio_player_start_failed',
        'end:play_failed',
      ]);
      expect(player.playing, isFalse);
    });

    test(
      'pause chama player somente quando esta tocando e sempre encerra sessao',
      () async {
        player.playing = true;

        await service.pause();

        expect(player.calls, ['pause']);
        expect(session.calls, ['end:pause']);

        player.calls.clear();
        session.calls.clear();
        player.playing = false;

        await service.pause();

        expect(player.calls, isEmpty);
        expect(session.calls, ['end:pause']);
      },
    );

    test('stop chama player.stop e encerra sessao', () async {
      await service.stop();

      expect(player.calls, ['stop']);
      expect(session.calls, ['end:stop']);
    });

    test(
      'stop libera estado e permite tocar o mesmo arquivo novamente',
      () async {
        await service.play(audioFile.path);
        player.calls.clear();
        session.calls.clear();

        await service.stop();
        await service.play(audioFile.path);

        expect(player.calls, ['stop', 'setLoopModeOff', 'seek:0', 'play']);
        expect(session.calls, ['end:stop', 'begin:audio_player_play']);
        expect(player.playing, isTrue);
      },
    );

    test('stop propaga erro do player sem mascarar', () async {
      final error = StateError('stop failed');
      player.stopError = error;

      await expectLater(service.stop(), throwsA(same(error)));
    });

    test(
      'dispose cancela assinatura, encerra sessao e descarta player',
      () async {
        await service.dispose();
        serviceDisposed = true;
        player.emitCompleted();

        expect(player.disposeCalls, 1);
        expect(session.calls, ['end:dispose']);
      },
    );

    test('playerStateStream completed encerra playback', () async {
      player.emitCompleted();
      await pumpEventQueue();

      expect(session.calls, ['end:playback_completed']);
    });

    test('novo service para playback anterior antes de tocar', () async {
      final otherPlayer = _FakeAudioPlayerClient();
      final otherSession = _FakeAudioPlaybackSessionClient();
      final otherService = AudioPlayerService.test(
        player: otherPlayer,
        sessionClient: otherSession,
      );
      addTearDown(() async {
        await otherService.dispose();
        await otherPlayer.closeStreams();
      });
      await service.play(audioFile.path);
      player.calls.clear();
      session.calls.clear();

      await otherService.play(audioFile.path);

      expect(player.calls, ['stop']);
      expect(session.calls, ['end:replaced_by_other_playback']);
      expect(otherPlayer.playing, isTrue);
    });

    test('streams de posicao e duracao sao expostos pelo service', () async {
      final positions = <Duration>[];
      final durations = <Duration?>[];
      final positionSub = service.positionStream.listen(positions.add);
      final durationSub = service.durationStream.listen(durations.add);

      player.emitPosition(const Duration(seconds: 3));
      player.emitDuration(const Duration(seconds: 12));
      await pumpEventQueue();

      expect(positions, [const Duration(seconds: 3)]);
      expect(durations, [const Duration(seconds: 12)]);

      await positionSub.cancel();
      await durationSub.cancel();
    });
  });
}

class _FakeAudioPlayerClient implements AudioPlayerClient {
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast(sync: true);

  final calls = <String>[];
  @override
  bool playing = false;
  Object? setFilePathError;
  Object? playError;
  Object? seekError;
  Object? stopError;
  bool blockStop = false;
  Completer<void>? _blockedStopCompleter;
  int disposeCalls = 0;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> setFilePath(String path) async {
    calls.add('setFilePath:$path');
    final error = setFilePathError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setLoopModeOff() async {
    calls.add('setLoopModeOff');
  }

  @override
  Future<void> play() async {
    calls.add('play');
    final error = playError;
    if (error != null) {
      throw error;
    }
    playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    final error = seekError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final error = stopError;
    if (error != null) {
      throw error;
    }
    if (blockStop) {
      _blockedStopCompleter = Completer<void>();
      await _blockedStopCompleter!.future;
    }
    playing = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  void emitCompleted() {
    playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.completed));
  }

  void completeBlockedStop() {
    blockStop = false;
    _blockedStopCompleter?.complete();
    _blockedStopCompleter = null;
  }

  void emitPosition(Duration position) {
    _positionController.add(position);
  }

  void emitDuration(Duration? duration) {
    _durationController.add(duration);
  }

  Future<void> closeStreams() async {
    await _playerStateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

class _FakeAudioPlaybackSessionClient implements AudioPlaybackSessionClient {
  final calls = <String>[];
  final startFailures = <_StartFailure>[];
  bool beginResult = true;

  @override
  Future<bool> beginPlayback({
    required String ownerId,
    required String reason,
  }) async {
    calls.add('begin:$reason');
    return beginResult;
  }

  @override
  void endPlayback({required String ownerId, required String reason}) {
    calls.add('end:$reason');
  }

  @override
  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  }) {
    startFailures.add(_StartFailure(reason: 'audio_player_start_failed'));
    calls.add('failure:audio_player_start_failed');
  }
}

class _StartFailure {
  const _StartFailure({required this.reason});

  final String reason;
}
