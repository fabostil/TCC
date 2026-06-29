import '../../../../editor/services/audio_player_service.dart';
import '../handlers/playback_command_handler.dart';

typedef ActivePlaybackPathResolver = String? Function();
typedef AudioPlayerServiceFactory = AudioPlayerService Function();

class LazyAudioPlayerPlaybackService implements PlaybackService {
  LazyAudioPlayerPlaybackService({
    required AudioPlayerServiceFactory playerServiceFactory,
    ActivePlaybackPathResolver? activePathResolver,
  }) : _playerServiceFactory = playerServiceFactory,
       _activePathResolver = activePathResolver;

  final AudioPlayerServiceFactory _playerServiceFactory;
  final ActivePlaybackPathResolver? _activePathResolver;
  AudioPlayerPlaybackService? _delegate;

  @override
  String? get currentPath {
    return _activePathResolver?.call() ?? _delegate?.currentPath;
  }

  AudioPlayerPlaybackService get _service {
    return _delegate ??= AudioPlayerPlaybackService(
      playerService: _playerServiceFactory(),
      activePathResolver: _activePathResolver,
    );
  }

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() => _service.stop();
}

class AudioPlayerPlaybackService implements PlaybackService {
  AudioPlayerPlaybackService({
    required AudioPlayerService playerService,
    ActivePlaybackPathResolver? activePathResolver,
  }) : _playerService = playerService,
       _activePathResolver = activePathResolver;

  final AudioPlayerService _playerService;
  final ActivePlaybackPathResolver? _activePathResolver;

  @override
  String? get currentPath =>
      _activePathResolver?.call() ?? _playerService.currentPath;

  @override
  Future<void> play() async {
    final path = currentPath;
    if (path == null || path.isEmpty) {
      throw StateError('Nenhuma gravacao ativa para reproduzir.');
    }
    await _playerService.play(path);
  }

  @override
  Future<void> pause() => _playerService.pause();

  @override
  Future<void> stop() => _playerService.stop();
}
