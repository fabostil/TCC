import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../../voices/coordination/voice_session_manager.dart';

class AudioPlayerService {
  AudioPlayerService({
    VoiceSessionManager? sessionManager,
    String ownerId = 'audio_playback',
  }) : _sessionManager = sessionManager ?? VoiceSessionManager.instance,
       _ownerId = ownerId {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _sessionManager.endPlayback(
          ownerId: _ownerId,
          reason: 'playback_completed',
        );
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final VoiceSessionManager _sessionManager;
  final String _ownerId;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  String? _currentPath;

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

    if (!await _sessionManager.beginPlayback(
      ownerId: _ownerId,
      reason: 'audio_player_play',
    )) {
      throw Exception(
        'Audio indisponivel: outra sessao esta usando o microfone.',
      );
    }

    if (_currentPath == path && _player.playing) {
      return;
    }

    try {
      if (_currentPath != path) {
        await _player.stop();
        await _player.setFilePath(path);
        _currentPath = path;
      }

      await _player.play();
    } catch (_) {
      _sessionManager.endPlayback(ownerId: _ownerId, reason: 'play_failed');
      rethrow;
    }
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
    }
    _sessionManager.endPlayback(ownerId: _ownerId, reason: 'pause');
  }

  Future<void> stop() async {
    await _player.stop();
    _sessionManager.endPlayback(ownerId: _ownerId, reason: 'stop');
  }

  Future<void> dispose() async {
    await _playerStateSubscription?.cancel();
    _sessionManager.endPlayback(ownerId: _ownerId, reason: 'dispose');
    await _player.dispose();
  }
}
