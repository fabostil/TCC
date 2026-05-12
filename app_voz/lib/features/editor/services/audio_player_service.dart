import 'dart:io';

import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  String? _currentPath;

  bool get isPlaying => _player.playing;
  String? get currentPath => _currentPath;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> play(String path) async {
    if (path.isEmpty) {
      throw Exception('Caminho do áudio vazio.');
    }

    final file = File(path);
    if (!await file.exists()) {
      _currentPath = null;
      throw Exception('Arquivo de áudio não encontrado.');
    }

    if (_currentPath == path && _player.playing) {
      return;
    }

    if (_currentPath != path) {
      await _player.stop();
      await _player.setFilePath(path);
      _currentPath = path;
    }

    await _player.play();
  }

  Future<void> pause() async {
    if (_player.playing) {
      await _player.pause();
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
