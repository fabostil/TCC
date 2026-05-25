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
