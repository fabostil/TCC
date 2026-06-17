import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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

class RecordingPlaybackResolution {
  const RecordingPlaybackResolution._({this.recording, this.message});

  final Gravacao? recording;
  final String? message;

  bool get canPlay => recording != null;

  factory RecordingPlaybackResolution.play(Gravacao recording) {
    return RecordingPlaybackResolution._(recording: recording);
  }

  factory RecordingPlaybackResolution.message(String message) {
    return RecordingPlaybackResolution._(message: message);
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

  Stream<PlayerState> get playerStateStream => _playerService.playerStateStream;

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
    if (state.playingRecordingId == gravacao.id) {
      await stopPlayback();
      return;
    }

    final previousPlayingId = state.playingRecordingId;
    if (previousPlayingId != null && previousPlayingId != gravacao.id) {
      await _playerService.stop();
      _setState(_state.copyWith(clearPlayingRecording: true));
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

  void handlePlayerState(PlayerState playerState) {
    if (playerState.processingState == ProcessingState.completed ||
        (_state.playingRecordingId != null &&
            !playerState.playing &&
            playerState.processingState == ProcessingState.idle)) {
      markPlaybackStopped();
    }
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

  Gravacao? findByPlaybackReference(String? reference) {
    final normalized = _commandService.normalize(reference ?? '');
    if (normalized.isEmpty) {
      return null;
    }

    final index = _playbackIndexFromReference(normalized);
    if (index != null) {
      if (index < 0 || index >= _state.recordings.length) {
        return null;
      }
      return _state.recordings[index];
    }

    return findByName(normalized);
  }

  bool isPlaybackReferenceOutOfRange(String? reference) {
    final normalized = _commandService.normalize(reference ?? '');
    final index = _playbackIndexFromReference(normalized);
    return index != null && (index < 0 || index >= _state.recordings.length);
  }

  RecordingPlaybackResolution resolvePlaybackCommand(String? reference) {
    if (_state.recordings.isEmpty) {
      return RecordingPlaybackResolution.message(
        'Não encontrei gravações para reproduzir. Grave um áudio no editor primeiro.',
      );
    }

    final trimmed = reference?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (_state.recordings.length == 1) {
        return RecordingPlaybackResolution.play(_state.recordings.single);
      }

      return RecordingPlaybackResolution.message(
        'Diga qual gravação deseja tocar, por exemplo: reproduzir gravação 1.',
      );
    }

    final recording = findByPlaybackReference(trimmed);
    if (recording != null) {
      return RecordingPlaybackResolution.play(recording);
    }

    return RecordingPlaybackResolution.message(
      isPlaybackReferenceOutOfRange(trimmed)
          ? 'Não encontrei essa gravação na lista.'
          : 'Não encontrei essa gravação. Diga o nome ou número da lista.',
    );
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

  int? _playbackIndexFromReference(String reference) {
    final numberMatch = RegExp(r'(^| )([0-9]+)( |$)').firstMatch(reference);
    final numericValue = int.tryParse(numberMatch?.group(2) ?? '');
    if (numericValue != null) {
      return numericValue - 1;
    }

    const numberWords = {
      'um': 0,
      'uma': 0,
      'dois': 1,
      'duas': 1,
      'tres': 2,
      'quatro': 3,
      'cinco': 4,
      'seis': 5,
      'sete': 6,
      'oito': 7,
      'nove': 8,
    };

    for (final entry in numberWords.entries) {
      if (RegExp('(^| )${entry.key}( |\$)').hasMatch(reference)) {
        return entry.value;
      }
    }

    const ordinals = {
      'primeira': 0,
      'primeiro': 0,
      'segunda': 1,
      'segundo': 1,
      'terceira': 2,
      'terceiro': 2,
      'quarta': 3,
      'quarto': 3,
      'quinta': 4,
      'quinto': 4,
    };

    for (final entry in ordinals.entries) {
      if (RegExp('(^| )${entry.key}( |\$)').hasMatch(reference)) {
        return entry.value;
      }
    }

    return null;
  }
}
