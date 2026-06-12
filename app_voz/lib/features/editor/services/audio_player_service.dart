import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../../voices/coordination/voice_diagnostics.dart';
import '../../voices/coordination/voice_session_manager.dart';

abstract class AudioPlayerClient {
  bool get playing;

  Stream<PlayerState> get playerStateStream;

  Stream<Duration> get positionStream;

  Stream<Duration?> get durationStream;

  Future<void> setFilePath(String path);

  Future<void> play();

  Future<void> seek(Duration position);

  Future<void> pause();

  Future<void> stop();

  Future<void> dispose();
}

class JustAudioPlayerClient implements AudioPlayerClient {
  JustAudioPlayerClient({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  bool get playing => _player.playing;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Future<void> setFilePath(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

abstract class AudioPlaybackSessionClient {
  Future<bool> beginPlayback({required String ownerId, required String reason});

  void endPlayback({required String ownerId, required String reason});

  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  });
}

class VoiceSessionAudioPlaybackClient implements AudioPlaybackSessionClient {
  const VoiceSessionAudioPlaybackClient(this._sessionManager);

  final VoiceSessionManager _sessionManager;

  @override
  Future<bool> beginPlayback({
    required String ownerId,
    required String reason,
  }) {
    return _sessionManager.beginPlayback(ownerId: ownerId, reason: reason);
  }

  @override
  void endPlayback({required String ownerId, required String reason}) {
    _sessionManager.endPlayback(ownerId: ownerId, reason: reason);
  }

  @override
  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  }) {
    _sessionManager.diagnostics.record(
      VoiceDiagnosticEventType.error,
      ownerId: ownerId,
      reason: 'audio_player_start_failed',
      message: 'Audio player failed to start playback.',
      metadata: {
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        'path': path,
      },
    );
  }
}

class AudioPlayerService {
  AudioPlayerService({
    VoiceSessionManager? sessionManager,
    AudioPlayerClient? player,
    AudioPlaybackSessionClient? sessionClient,
    String ownerId = 'audio_playback',
  }) : _player = player ?? JustAudioPlayerClient(),
       _sessionClient =
           sessionClient ??
           VoiceSessionAudioPlaybackClient(
             sessionManager ?? VoiceSessionManager.instance,
           ),
       _ownerId = ownerId {
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
  }

  AudioPlayerService.test({
    required AudioPlayerClient player,
    required AudioPlaybackSessionClient sessionClient,
    String ownerId = 'audio_playback',
  }) : _player = player,
       _sessionClient = sessionClient,
       _ownerId = ownerId {
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
  }

  final AudioPlayerClient _player;
  final AudioPlaybackSessionClient _sessionClient;
  final String _ownerId;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  String? _currentPath;
  bool _restartCurrentPathFromBeginning = false;
  Future<void>? _completionResetFuture;

  bool get isPlaying => _player.playing;
  String? get currentPath => _currentPath;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> play(String path) async {
    if (path.isEmpty) {
      throw Exception('Caminho do audio vazio.');
    }

    final file = File(path);
    if (!await file.exists()) {
      _currentPath = null;
      throw Exception('Arquivo de audio nao encontrado.');
    }

    if (_currentPath == path && _player.playing) {
      return;
    }

    if (!await _sessionClient.beginPlayback(
      ownerId: _ownerId,
      reason: 'audio_player_play',
    )) {
      throw Exception(
        'Áudio indisponível: outra sessão está usando o microfone.',
      );
    }

    try {
      final completionResetFuture = _completionResetFuture;
      if (completionResetFuture != null) {
        await completionResetFuture;
      }

      if (_currentPath != path) {
        await _player.stop();
        await _player.setFilePath(path);
        _currentPath = path;
        _restartCurrentPathFromBeginning = false;
      } else if (_restartCurrentPathFromBeginning) {
        await _player.seek(Duration.zero);
        _restartCurrentPathFromBeginning = false;
      }

      await _player.play();
    } catch (error, stackTrace) {
      _sessionClient.recordStartFailure(
        ownerId: _ownerId,
        error: error,
        stackTrace: stackTrace,
        path: path,
      );
      _sessionClient.endPlayback(ownerId: _ownerId, reason: 'play_failed');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
    }
    _sessionClient.endPlayback(ownerId: _ownerId, reason: 'pause');
  }

  Future<void> stop() async {
    await _player.stop();
    _restartCurrentPathFromBeginning = true;
    _sessionClient.endPlayback(ownerId: _ownerId, reason: 'stop');
  }

  Future<void> dispose() async {
    await _playerStateSubscription?.cancel();
    _sessionClient.endPlayback(ownerId: _ownerId, reason: 'dispose');
    await _player.dispose();
  }

  void _handlePlayerState(PlayerState state) {
    if (state.processingState != ProcessingState.completed) {
      return;
    }

    _restartCurrentPathFromBeginning = true;
    _sessionClient.endPlayback(ownerId: _ownerId, reason: 'playback_completed');
    _completionResetFuture = _resetCompletedPlayback();
  }

  Future<void> _resetCompletedPlayback() async {
    try {
      await _player.seek(Duration.zero);
      _restartCurrentPathFromBeginning = false;
    } catch (_) {
      _restartCurrentPathFromBeginning = true;
    } finally {
      _completionResetFuture = null;
    }
  }
}
