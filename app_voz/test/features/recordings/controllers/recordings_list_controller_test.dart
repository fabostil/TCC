import 'dart:async';

import 'package:app_voz/features/editor/services/audio_player_service.dart';
import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  group('RecordingsListController', () {
    late FakeRecordingManagementService recordingService;
    late FakeAudioPlayerService playerService;
    late RecordingsListController controller;

    setUp(() {
      recordingService = FakeRecordingManagementService();
      playerService = FakeAudioPlayerService();
      controller = RecordingsListController(
        recordingService: recordingService,
        playerService: playerService,
      );
    });

    tearDown(() {
      controller.dispose();
      playerService.close();
    });

    test('carrega gravacoes por usuario e termo de busca', () async {
      recordingService.recordings = [
        _recording(id: 1, name: 'Refrao'),
        _recording(id: 2, name: 'Guia'),
      ];

      await controller.load(usuarioId: 10, searchTerm: 'ref');

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isNull);
      expect(controller.state.searchTerm, 'ref');
      expect(controller.state.recordings.map((item) => item.nome), [
        'Refrao',
        'Guia',
      ]);
      expect(recordingService.lastUserId, 10);
      expect(recordingService.lastSearchTerm, 'ref');
    });

    test('expõe erro quando usuario nao possui id', () async {
      await controller.load(usuarioId: null);

      expect(controller.state.loading, isFalse);
      expect(controller.state.hasError, isTrue);
      expect(controller.state.recordings, isEmpty);
    });

    test('carrega gravacoes por projeto', () async {
      recordingService.recordings = [_recording(id: 1, name: 'Take')];

      await controller.loadByProject(projetoId: 99);

      expect(controller.state.loading, isFalse);
      expect(controller.state.recordings.single.nome, 'Take');
      expect(recordingService.lastProjectId, 99);
    });

    test('busca gravacao por nome normalizado', () async {
      recordingService.recordings = [_recording(id: 1, name: 'Ideia acústica')];
      await controller.load(usuarioId: 10);

      final found = controller.findByName('acustica');

      expect(found, isNotNull);
      expect(found!.id, 1);
    });

    test('renomeia gravacao e atualiza estado local', () async {
      final original = _recording(id: 1, name: 'Demo');
      recordingService.recordings = [original];
      await controller.load(usuarioId: 10);

      final updated = await controller.renameRecording(
        gravacao: original,
        newName: 'Demo final',
        usuarioId: null,
      );

      expect(updated.nome, 'Demo final');
      expect(controller.state.recordings.single.nome, 'Demo final');
      expect(recordingService.lastRenamedName, 'Demo final');
    });

    test('exclui gravacao, limpa pendencia e para playback ativo', () async {
      final recording = _recording(id: 1, name: 'Take');
      recordingService.recordings = [recording];
      await controller.load(usuarioId: 10);
      controller.requestDeletion(recording);
      playerService.playing = true;
      await controller.togglePlayback(recording, usuarioId: null);

      await controller.deleteRecording(gravacao: recording, usuarioId: null);

      expect(controller.state.recordings, isEmpty);
      expect(controller.state.pendingDeletion, isNull);
      expect(controller.state.playingRecordingId, isNull);
      expect(recordingService.deletedIds, [1]);
      expect(playerService.stopCalls, 1);
    });

    test(
      'play muda estado para parar imediatamente e stop volta para play',
      () async {
        final recording = _recording(id: 1, name: 'Take');
        recordingService.recordings = [recording];
        await controller.load(usuarioId: 10);

        await controller.togglePlayback(recording, usuarioId: null);

        expect(controller.state.playingRecordingId, 1);
        expect(playerService.playedPaths, ['/tmp/1.m4a']);

        await controller.togglePlayback(recording, usuarioId: null);

        expect(controller.state.playingRecordingId, isNull);
        expect(playerService.stopCalls, 1);
      },
    );

    test(
      'stop usa estado visual mesmo se player ja nao reporta playing',
      () async {
        final recording = _recording(id: 1, name: 'Take');
        recordingService.recordings = [recording];
        await controller.load(usuarioId: 10);
        await controller.togglePlayback(recording, usuarioId: null);
        playerService.playing = false;

        await controller.togglePlayback(recording, usuarioId: null);

        expect(controller.state.playingRecordingId, isNull);
        expect(playerService.stopCalls, 1);
        expect(playerService.playedPaths, ['/tmp/1.m4a']);
      },
    );

    test('conclusao limpa estado sem reiniciar reproducao', () async {
      final recording = _recording(id: 1, name: 'Take');
      recordingService.recordings = [recording];
      await controller.load(usuarioId: 10);
      await controller.togglePlayback(recording, usuarioId: null);

      controller.handlePlayerState(
        PlayerState(false, ProcessingState.completed),
      );

      expect(controller.state.playingRecordingId, isNull);
      expect(playerService.playedPaths, ['/tmp/1.m4a']);
    });

    test(
      'idle sem playing limpa estado apos parada externa do player',
      () async {
        final recording = _recording(id: 1, name: 'Take');
        recordingService.recordings = [recording];
        await controller.load(usuarioId: 10);
        await controller.togglePlayback(recording, usuarioId: null);

        controller.handlePlayerState(PlayerState(false, ProcessingState.idle));

        expect(controller.state.playingRecordingId, isNull);
      },
    );

    test('replay manual da mesma gravacao funciona apos conclusao', () async {
      final recording = _recording(id: 1, name: 'Take');
      recordingService.recordings = [recording];
      await controller.load(usuarioId: 10);

      await controller.togglePlayback(recording, usuarioId: null);
      controller.handlePlayerState(
        PlayerState(false, ProcessingState.completed),
      );
      await controller.togglePlayback(recording, usuarioId: null);

      expect(controller.state.playingRecordingId, 1);
      expect(playerService.playedPaths, ['/tmp/1.m4a', '/tmp/1.m4a']);
    });

    test('trocar gravacao para anterior e toca nova', () async {
      final first = _recording(id: 1, name: 'Primeira');
      final second = _recording(id: 2, name: 'Segunda');
      recordingService.recordings = [first, second];
      await controller.load(usuarioId: 10);

      await controller.togglePlayback(first, usuarioId: null);
      await controller.togglePlayback(second, usuarioId: null);

      expect(controller.state.playingRecordingId, 2);
      expect(playerService.stopCalls, 1);
      expect(playerService.playedPaths, ['/tmp/1.m4a', '/tmp/2.m4a']);
    });

    test('resolve comando por titulo exato antes de posicao visual', () async {
      final visualOrder = [
        _recording(id: 6, name: 'Gravacao 3'),
        _recording(id: 5, name: 'Gravacao 2'),
        _recording(id: 4, name: 'Gravacao 1'),
        _recording(id: 3, name: 'Quarta'),
        _recording(id: 2, name: 'Quinta'),
        _recording(id: 1, name: 'Mais antiga'),
      ];
      recordingService.recordings = visualOrder;
      await controller.load(usuarioId: 10);

      expect(
        controller.resolvePlaybackCommand('gravacao 1').recording,
        visualOrder[2],
      );
      expect(
        controller.resolvePlaybackCommand('tocar gravacao 1').recording,
        visualOrder[2],
      );
      expect(
        controller.resolvePlaybackCommand('gravacao 3').recording,
        visualOrder[0],
      );
      expect(
        controller.resolvePlaybackCommand('item 1').recording,
        visualOrder[0],
      );
      expect(
        controller.resolvePlaybackCommand('tocar item 1').recording,
        visualOrder[0],
      );
      expect(
        controller.resolvePlaybackCommand('item 2').recording,
        visualOrder[1],
      );
      expect(
        controller.resolvePlaybackCommand('segunda gravacao').recording,
        visualOrder[1],
      );
      expect(
        controller.resolvePlaybackCommand('tocar a segunda gravacao').recording,
        visualOrder[1],
      );
      expect(
        controller.resolvePlaybackCommand('primeira gravacao').recording,
        visualOrder[0],
      );
      expect(
        controller.resolvePlaybackCommand('a primeira').recording,
        visualOrder[0],
      );
    });

    test('gravacao numerada resolve por indice visual quando nao ha titulo correspondente', () async {
      final recordings = [
        _recording(id: 6, name: 'Mais recente'),
        _recording(id: 5, name: 'Segunda visivel'),
      ];
      recordingService.recordings = recordings;
      await controller.load(usuarioId: 10);

      // "gravacao 1" → first visual item (index 0)
      expect(controller.resolvePlaybackCommand('gravacao 1').recording, recordings[0]);
      // "gravacao 2" → second visual item (index 1)
      expect(controller.resolvePlaybackCommand('gravacao 2').recording, recordings[1]);
      // "gravacao 3" → out of range → null
      final outOfRange = controller.resolvePlaybackCommand('gravacao 3');
      expect(outOfRange.recording, isNull);
      expect(outOfRange.message, 'Não encontrei essa gravação na lista.');
    });

    test(
      'comando ambiguo com varias gravacoes nao toca automaticamente',
      () async {
        recordingService.recordings = [
          _recording(id: 1, name: 'Primeira'),
          _recording(id: 2, name: 'Segunda'),
        ];
        await controller.load(usuarioId: 10);

        final resolution = controller.resolvePlaybackCommand(null);

        expect(resolution.recording, isNull);
        expect(
        resolution.message,
        'Diga qual gravação deseja tocar, por exemplo: tocar item 1.',
      );
      },
    );

    test('comando ambiguo com uma gravacao toca a unica', () async {
      final only = _recording(id: 1, name: 'Unica');
      recordingService.recordings = [only];
      await controller.load(usuarioId: 10);

      expect(controller.resolvePlaybackCommand(null).recording, only);
    });

    test('numero inexistente retorna mensagem amigavel', () async {
      recordingService.recordings = [_recording(id: 1, name: 'Primeira')];
      await controller.load(usuarioId: 10);

      final resolution = controller.resolvePlaybackCommand('item 2');

      expect(resolution.recording, isNull);
      expect(resolution.message, 'Não encontrei essa gravação na lista.');
    });
  });
}

Gravacao _recording({required int id, required String name}) {
  return Gravacao(
    id: id,
    usuarioId: 10,
    nome: name,
    caminhoArquivo: '/tmp/$id.m4a',
    dataCriacao: '2026-05-19T10:00:00.000',
    tamanhoBytes: 128,
  );
}

class FakeRecordingManagementService extends RecordingManagementService {
  List<Gravacao> recordings = [];
  int? lastUserId;
  int? lastProjectId;
  String? lastSearchTerm;
  String? lastRenamedName;
  final deletedIds = <int>[];

  @override
  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    lastUserId = usuarioId;
    lastSearchTerm = termoBusca;
    return recordings;
  }

  @override
  Future<List<Gravacao>> listByProjectWithFileState(
    int projetoId, {
    String? termoBusca,
    String? status,
  }) async {
    lastProjectId = projetoId;
    lastSearchTerm = termoBusca;
    return recordings;
  }

  @override
  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String novoNome,
    required List<Gravacao> gravacoesRelacionadas,
  }) async {
    lastRenamedName = novoNome;
    return gravacao.copyWith(nome: novoNome);
  }

  @override
  Future<void> deleteRecording(Gravacao gravacao) async {
    deletedIds.add(gravacao.id!);
  }
}

class FakeAudioPlayerService implements AudioPlayerService {
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  bool playing = false;
  int stopCalls = 0;
  final playedPaths = <String>[];

  @override
  String? currentPath;

  @override
  bool get isPlaying => playing;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> play(String path) async {
    currentPath = path;
    playedPaths.add(path);
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<void> dispose() async {}

  void close() {
    _playerStateController.close();
    _positionController.close();
    _durationController.close();
  }
}
