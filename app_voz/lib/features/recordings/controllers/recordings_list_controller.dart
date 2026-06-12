import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/user_facing_messages.dart';
import '../../../models/gravacao.dart';
import '../../../repositories/historico_repository.dart';
import '../../editor/services/audio_player_service.dart';
import '../../voices/services/command_service.dart';
import '../services/recording_management_service.dart';

class RecordingsListState {
  final bool loading;
  final String? error;
  final List<Gravacao> recordings;
  final int? playingRecordingId;
  final Gravacao? pendingDeletion;
  final String searchTerm;

  const RecordingsListState({
    required this.loading,
    required this.error,
    required this.recordings,
    required this.playingRecordingId,
    required this.pendingDeletion,
    required this.searchTerm,
  });

  const RecordingsListState.initial()
    : loading = true,
      error = null,
      recordings = const [],
      playingRecordingId = null,
      pendingDeletion = null,
      searchTerm = '';

  bool get hasError => error != null;

  RecordingsListState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<Gravacao>? recordings,
    int? playingRecordingId,
    bool clearPlayingRecording = false,
    Gravacao? pendingDeletion,
    bool clearPendingDeletion = false,
    String? searchTerm,
  }) {
    return RecordingsListState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      recordings: recordings ?? this.recordings,
      playingRecordingId: clearPlayingRecording
          ? null
          : playingRecordingId ?? this.playingRecordingId,
      pendingDeletion: clearPendingDeletion
          ? null
          : pendingDeletion ?? this.pendingDeletion,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }
}

class RecordingsListController extends ChangeNotifier {
  RecordingsListController({
    RecordingManagementService? recordingService,
    AudioPlayerService? playerService,
    HistoricoRepository? historicoRepository,
    CommandService commandService = const CommandService(),
  }) : _recordingService = recordingService ?? RecordingManagementService(),
       _playerService = playerService ?? AudioPlayerService(),
       _historicoRepository =
           historicoRepository ?? HistoricoRepository.instance,
       _commandService = commandService;

  final RecordingManagementService _recordingService;
  final AudioPlayerService _playerService;
  final HistoricoRepository _historicoRepository;
  final CommandService _commandService;

  RecordingsListState _state = const RecordingsListState.initial();

  RecordingsListState get state => _state;

  Stream<dynamic> get playerStateStream => _playerService.playerStateStream;

  bool get isPlaying => _playerService.isPlaying;

  Future<void> load({required int? usuarioId, String? searchTerm}) async {
    final effectiveSearchTerm = searchTerm ?? _state.searchTerm;

    if (usuarioId == null) {
      _setState(
        _state.copyWith(
          loading: false,
          error: 'Usuario sem identificacao para buscar gravacoes.',
          searchTerm: effectiveSearchTerm,
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        loading: true,
        clearError: true,
        searchTerm: effectiveSearchTerm,
      ),
    );

    try {
      final recordings = await _recordingService.listByUserWithFileState(
        usuarioId,
        termoBusca: effectiveSearchTerm,
      );
      _setState(_state.copyWith(loading: false, recordings: recordings));
    } catch (_) {
      _setState(
        _state.copyWith(
          loading: false,
          error: UserFacingMessages.dataLoadError,
        ),
      );
    }
  }

  Future<void> loadByProject({
    required int? projetoId,
    String? searchTerm,
  }) async {
    final effectiveSearchTerm = searchTerm ?? _state.searchTerm;

    if (projetoId == null) {
      _setState(
        _state.copyWith(
          loading: false,
          error: 'Projeto sem identificacao para buscar gravacoes.',
          searchTerm: effectiveSearchTerm,
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        loading: true,
        clearError: true,
        searchTerm: effectiveSearchTerm,
      ),
    );

    try {
      final recordings = await _recordingService.listByProjectWithFileState(
        projetoId,
        termoBusca: effectiveSearchTerm,
      );
      _setState(_state.copyWith(loading: false, recordings: recordings));
    } catch (_) {
      _setState(
        _state.copyWith(
          loading: false,
          error: UserFacingMessages.dataLoadError,
        ),
      );
    }
  }

  Future<void> togglePlayback(
    Gravacao gravacao, {
    required int? usuarioId,
  }) async {
    if (state.playingRecordingId == gravacao.id && _playerService.isPlaying) {
      await stopPlayback();
      return;
    }

    await _playerService.play(gravacao.caminhoArquivo);
    _setState(_state.copyWith(playingRecordingId: gravacao.id));

    unawaited(
      _recordHistory(
        usuarioId: usuarioId,
        tipo: 'gravacao_reproduzida',
        descricao: 'Reproduziu a gravacao "${gravacao.nome}"',
        gravacaoId: gravacao.id,
        projetoId: gravacao.projetoId,
      ),
    );
  }

  Future<void> stopPlayback() async {
    await _playerService.stop();
    markPlaybackStopped();
  }

  void markPlaybackStopped() {
    if (_state.playingRecordingId == null) {
      return;
    }

    _setState(_state.copyWith(clearPlayingRecording: true));
  }

  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String newName,
    required int? usuarioId,
    bool byVoice = false,
  }) async {
    final updated = await _recordingService.renameRecording(
      gravacao: gravacao,
      novoNome: newName,
      gravacoesRelacionadas: _state.recordings,
    );
    final recordings = [..._state.recordings];
    final index = recordings.indexWhere((item) => item.id == gravacao.id);
    if (index != -1) {
      recordings[index] = updated;
      _setState(_state.copyWith(recordings: recordings));
    }

    unawaited(
      _recordHistory(
        usuarioId: usuarioId,
        tipo: 'gravacao_renomeada',
        descricao:
            'Renomeou "${gravacao.nome}" para "${updated.nome}"${byVoice ? ' por voz' : ''}',
        gravacaoId: gravacao.id,
        projetoId: gravacao.projetoId,
      ),
    );

    return updated;
  }

  Future<void> deleteRecording({
    required Gravacao gravacao,
    required int? usuarioId,
    bool byVoice = false,
  }) async {
    if (_state.playingRecordingId == gravacao.id) {
      await _playerService.stop();
    }

    await _recordingService.deleteRecording(gravacao);
    final recordings = _state.recordings
        .where((item) => item.id != gravacao.id)
        .toList();
    _setState(
      _state.copyWith(
        recordings: recordings,
        clearPendingDeletion: true,
        clearPlayingRecording: _state.playingRecordingId == gravacao.id,
      ),
    );

    unawaited(
      _recordHistory(
        usuarioId: usuarioId,
        tipo: 'gravacao_excluida',
        descricao:
            'Excluiu a gravacao "${gravacao.nome}"${byVoice ? ' por voz' : ''}',
        projetoId: gravacao.projetoId,
      ),
    );
  }

  void requestDeletion(Gravacao gravacao) {
    _setState(_state.copyWith(pendingDeletion: gravacao));
  }

  void cancelPendingDeletion() {
    _setState(_state.copyWith(clearPendingDeletion: true));
  }

  Gravacao? findByName(String? name) {
    final normalizedName = _commandService.normalize(name ?? '');
    if (normalizedName.isEmpty) {
      return null;
    }

    for (final recording in _state.recordings) {
      if (_commandService.normalize(recording.nome).contains(normalizedName)) {
        return recording;
      }
    }

    return null;
  }

  @override
  void dispose() {
    unawaited(_playerService.dispose());
    super.dispose();
  }

  void _setState(RecordingsListState nextState) {
    _state = nextState;
    notifyListeners();
  }

  Future<void> _recordHistory({
    required int? usuarioId,
    required String tipo,
    required String descricao,
    int? gravacaoId,
    int? projetoId,
  }) async {
    if (usuarioId == null) {
      return;
    }

    try {
      await _historicoRepository.registrar(
        usuarioId: usuarioId,
        tipo: tipo,
        descricao: descricao,
        gravacaoId: gravacaoId,
        projetoId: projetoId,
      );
    } catch (e) {
      debugPrint('Erro ao registrar historico persistente: $e');
    }
  }
}
