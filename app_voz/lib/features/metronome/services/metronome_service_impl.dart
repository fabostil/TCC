import 'dart:async';

import 'package:flutter/services.dart';

import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/realtime/dispatch/contratos/audio_output_guard.dart';
import '../../voices/realtime/dispatch/handlers/metronome_command_handler.dart';

class MetronomeServiceImpl implements MetronomeService {
  MetronomeServiceImpl({
    AudioOutputGuard? audioOutputGuard,
    VoiceSessionManager? sessionManager,
    bool Function()? canPlayTick,
    Future<void> Function()? tickPlayer,
  }) : _audioOutputGuard =
           audioOutputGuard ??
           LazyAudioOutputGuard(() => VoiceSessionManager.instance),
       _usesDefaultAudioOutputGuard = audioOutputGuard == null,
       _sessionManager = sessionManager,
       _canPlayTickOverride = canPlayTick,
       _tickPlayer =
           tickPlayer ?? (() => SystemSound.play(SystemSoundType.click));

  final AudioOutputGuard _audioOutputGuard;
  final bool _usesDefaultAudioOutputGuard;
  final VoiceSessionManager? _sessionManager;
  final bool Function()? _canPlayTickOverride;
  final Future<void> Function() _tickPlayer;

  Timer? _timer;
  int? _activeBpm;

  @override
  bool get isRunning => _timer?.isActive ?? false;
  int? get activeBpm => _activeBpm;

  @override
  Future<void> start(int bpm) async {
    _validateBpm(bpm);
    if (isRunning && _activeBpm == bpm) {
      return;
    }

    await stop();
    _activeBpm = bpm;
    final interval = Duration(milliseconds: (60000 / bpm).round());
    _timer = Timer.periodic(interval, (_) {
      if (_canPlayTick()) {
        unawaited(_tickPlayer());
      }
    });
  }

  @override
  Future<void> updateBpm(int bpm) => start(bpm);

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _activeBpm = null;
  }

  @override
  Future<void> dispose() => stop();

  bool _canPlayTick() {
    final override = _canPlayTickOverride;
    if (override != null) {
      return override();
    }
    final session = _sessionManager;
    if (session != null &&
        (session.recordingActive ||
            session.playbackActive ||
            session.listeningActive)) {
      return false;
    }
    if (session == null && _usesDefaultAudioOutputGuard) {
      final defaultSession = VoiceSessionManager.instance;
      if (defaultSession.recordingActive ||
          defaultSession.playbackActive ||
          defaultSession.listeningActive) {
        return false;
      }
    }
    return _audioOutputGuard.isAudioOutputAvailable();
  }

  void _validateBpm(int bpm) {
    if (bpm <= 0) {
      throw ArgumentError.value(bpm, 'bpm', 'BPM deve ser positivo.');
    }
  }
}
