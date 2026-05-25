abstract class AudioOutputGuard {
  bool isAudioOutputAvailable();
}

typedef AudioOutputGuardFactory = AudioOutputGuard Function();

class LazyAudioOutputGuard implements AudioOutputGuard {
  LazyAudioOutputGuard(this._factory);

  final AudioOutputGuardFactory _factory;
  AudioOutputGuard? _delegate;

  @override
  bool isAudioOutputAvailable() {
    return (_delegate ??= _factory()).isAudioOutputAvailable();
  }
}
