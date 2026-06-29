abstract class AudioOutputGuard {
  bool isAudioOutputAvailable();

  Future<bool> beginAudioOutput({required String ownerId, String? reason});

  void endAudioOutput({required String ownerId, String? reason});
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

  @override
  Future<bool> beginAudioOutput({required String ownerId, String? reason}) {
    return (_delegate ??= _factory()).beginAudioOutput(
      ownerId: ownerId,
      reason: reason,
    );
  }

  @override
  void endAudioOutput({required String ownerId, String? reason}) {
    (_delegate ??= _factory()).endAudioOutput(ownerId: ownerId, reason: reason);
  }
}
