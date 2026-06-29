import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/ui/user_facing_messages.dart';
import '../../../models/gravacao.dart';
import '../../voices/coordination/voice_diagnostics.dart';
import '../../voices/coordination/voice_session_manager.dart';
import '../../voices/realtime/runtime/voice_realtime_ecosystem.dart';
import '../../voices/realtime/voice_realtime_events.dart';
import '../../voices/realtime/infrastructure/bridge/audio_stream_shadow_router.dart';
import '../services/audio_recording_capture.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recording_service.dart';
import '../services/stream_first_audio_recording_service.dart';

typedef RecordingFinalizer =
    Future<Gravacao> Function({
      required String path,
      required DateTime startedAt,
      required bool automatic,
    });

typedef RecordingHistoryWriter =
    void Function(
      String action,
      String type, {
      int? recordingId,
      int? projectId,
    });

class RecordingRealtimeState {
  const RecordingRealtimeState({
    this.recording = false,
    this.paused = false,
    this.playing = false,
    this.processing = false,
    this.currentPath,
    this.startedAt,
    this.currentAmplitude = -160.0,
    this.silenceMs = 0,
    this.timelineProgress = 0.0,
    this.statusMessage = 'Projeto pronto para gravar.',
  });

  final bool recording;
  final bool paused;
  final bool playing;
  final bool processing;
  final String? currentPath;
  final DateTime? startedAt;
  final double currentAmplitude;
  final int silenceMs;
  final double timelineProgress;
  final String statusMessage;

  bool get canStartRecording => !recording && !processing && !playing;
  bool get canPauseRecording => recording && !paused && !processing;
  bool get canResumeRecording => recording && paused && !processing;
  bool get canStopRecording => recording && !processing;
  bool get canPlay => !recording && !processing && !playing;
  bool get canStopPlayback => playing && !processing;

  RecordingRealtimeState copyWith({
    bool? recording,
    bool? paused,
    bool? playing,
    bool? processing,
    String? currentPath,
    bool clearCurrentPath = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    double? currentAmplitude,
    int? silenceMs,
    double? timelineProgress,
    String? statusMessage,
  }) {
    return RecordingRealtimeState(
      recording: recording ?? this.recording,
      paused: paused ?? this.paused,
      playing: playing ?? this.playing,
      processing: processing ?? this.processing,
      currentPath: clearCurrentPath ? null : currentPath ?? this.currentPath,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      currentAmplitude: currentAmplitude ?? this.currentAmplitude,
      silenceMs: silenceMs ?? this.silenceMs,
      timelineProgress: _clampProgress(
        timelineProgress ?? this.timelineProgress,
      ),
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  static double _clampProgress(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class RecordingRealtimeCoordinator extends ChangeNotifier {
  RecordingRealtimeCoordinator({
    AudioRecordingCapture? recordingService,
    AudioPlayerService? playerService,
    AudioStreamShadowRouter? shadowRouter,
    VoiceSessionManager? sessionManager,
    this.ownerId = 'editor',
    int silenceLimitMs = 6000,
    double silenceThresholdDb = defaultSilenceThresholdDb,
    bool automaticSilenceStop = true,
    bool observeLifecycle = true,
    Future<void> Function(String reason)? realtimeShutdown,
  }) : _recordingService = recordingService ?? _createRecordingService(ownerId),
       _playerService = playerService ?? AudioPlayerService(ownerId: ownerId),
       _shadowRouter = shadowRouter ?? AudioStreamShadowRouter(),
       _sessionManager = sessionManager ?? VoiceSessionManager.instance,
       _realtimeShutdown =
           realtimeShutdown ??
           ((reason) =>
               VoiceRealtimeEcosystem.instance.shutdown(reason: reason)),
       _silenceLimitMs = silenceLimitMs,
       _silenceThresholdDb = silenceThresholdDb,
       _automaticSilenceStop = automaticSilenceStop {
    _playerStateSubscription = _playerService.playerStateStream.listen((state) {
      if (!state.playing && _state.playing) {
        _playbackDuration = null;
        _setState(
          _state.copyWith(
            playing: false,
            timelineProgress: 0.0,
            statusMessage: 'Reprodução finalizada.',
          ),
        );
      }
    });
    _playbackPositionSubscription = _playerService.positionStream.listen(
      _handlePlaybackPosition,
    );
    _playbackDurationSubscription = _playerService.durationStream.listen(
      (duration) => _playbackDuration = duration,
    );
    if (observeLifecycle) {
      _lifecycleListener = AppLifecycleListener(
        onStateChange: _handleLifecycleStateChanged,
      );
    }
  }

  static const int silenceMonitorIntervalMs = 500;
  static const double defaultSilenceThresholdDb = -30.0;
  // Keep the legacy constant for tests that reference it directly.
  static const double silenceThresholdDb = defaultSilenceThresholdDb;
  static const bool _useStreamFirstMode = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  final AudioRecordingCapture _recordingService;
  final AudioPlayerService _playerService;
  final AudioStreamShadowRouter _shadowRouter;
  final VoiceSessionManager _sessionManager;
  final Future<void> Function(String reason) _realtimeShutdown;
  final String ownerId;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription<Duration>? _playbackPositionSubscription;
  StreamSubscription<Duration?>? _playbackDurationSubscription;
  Timer? _silenceTimer;
  Timer? _recordingProgressTimer;
  AppLifecycleListener? _lifecycleListener;
  Duration? _playbackDuration;
  int _silenceLimitMs;
  double _silenceThresholdDb;
  bool _automaticSilenceStop;
  bool _wasRecordingBeforeLifecyclePause = false;
  bool _wasSttActiveBeforeLifecyclePause = false;
  bool _pausedByLifecycle = false;
  bool _captureClosedByLifecycle = false;
  bool _handlingLifecycle = false;
  bool _disposed = false;
  bool _isStopping = false;

  RecordingRealtimeState _state = const RecordingRealtimeState();

  RecordingRealtimeState get state => _state;

  bool get pausedByLifecycle => _pausedByLifecycle;

  bool get wasRecordingBeforeLifecyclePause =>
      _wasRecordingBeforeLifecyclePause;

  bool get wasSttActiveBeforeLifecyclePause =>
      _wasSttActiveBeforeLifecyclePause;

  Stream<Uint8List> get rawAudioChunks => _recordingService.rawAudioChunks;

  @visibleForTesting
  static const int recordingTimelineFallbackSeconds = 180;

  int get silenceLimitMs => _silenceLimitMs;

  bool get automaticSilenceStop => _automaticSilenceStop;

  static AudioRecordingCapture _createRecordingService(String ownerId) {
    if (_useStreamFirstMode) {
      return StreamFirstAudioRecordingService(ownerId: ownerId);
    }
    return AudioRecordingService(ownerId: ownerId);
  }

  void applySettings({
    required bool automaticSilenceStop,
    required int silenceLimitMs,
    double? silenceThresholdDb,
  }) {
    _automaticSilenceStop = automaticSilenceStop;
    _silenceLimitMs = silenceLimitMs;
    if (silenceThresholdDb != null) {
      _silenceThresholdDb = silenceThresholdDb;
    }
  }

  Future<void> startRecording({
    required RecordingFinalizer finalizeRecording,
    required RecordingHistoryWriter onHistory,
    Future<void> Function()? onAutomaticStop,
  }) async {
    if (_state.recording) {
      _setStatus('Já existe uma gravação em andamento.');
      return;
    }

    if (_state.processing) {
      _setStatus('Aguarde o processamento atual terminar.');
      return;
    }

    if (_state.playing) {
      await stopPlayback();
    }

    final hasPermission = await _checkMicrophonePermissionBeforeCapture();
    if (!hasPermission) {
      _publishMicrophonePermissionLost(
        reason: 'microphone_permission_denied_before_recording',
      );
      _setState(
        _state.copyWith(
          processing: false,
          statusMessage:
              'Permissão do microfone removida. Reative para gravar novamente.',
        ),
      );
      return;
    }

    _sessionManager.diagnostics.record(
      VoiceDiagnosticEventType.recordingStarted,
      ownerId: ownerId,
      reason: 'recording_intent',
      message: 'Intenção de iniciar gravação recebida.',
    );
    _setState(
      _state.copyWith(
        processing: true,
        statusMessage: 'Preparando gravação...',
      ),
    );

    try {
      final path = await _recordingService.startRecording();
      _shadowRouter.start(
        _recordingService.rawAudioChunks,
        correlationId:
            'recording_shadow_${DateTime.now().microsecondsSinceEpoch}',
      );
      _setState(
        _state.copyWith(
          recording: true,
          paused: false,
          playing: false,
          processing: false,
          currentPath: path,
          startedAt: DateTime.now(),
          currentAmplitude: -160.0,
          silenceMs: 0,
          timelineProgress: 0.0,
          statusMessage: 'Gravação real iniciada.',
        ),
      );
      _clearLifecyclePauseFlags();
      _startRecordingProgressTimer();
      _startSilenceMonitoring(finalizeRecording, onHistory, onAutomaticStop);
      onHistory('Iniciou gravação real', 'gravacao_iniciada');
    } catch (e) {
      if (_isMicrophonePermissionError(e)) {
        await _handleMicrophonePermissionLost(
          reason: 'microphone_permission_lost_during_start',
          error: e,
        );
        return;
      }
      _sessionManager.registerFailure(
        ownerId: ownerId,
        reason: 'recording_start_failed',
        message: UserFacingMessages.recordingControlError,
      );
      _setState(
        _state.copyWith(
          processing: false,
          statusMessage: UserFacingMessages.recordingControlError,
        ),
      );
      rethrow;
    }
  }

  Future<void> pauseRecording({
    required void Function(String action, String type) onHistory,
  }) async {
    if (!_state.recording) {
      _setStatus('Não existe gravação em andamento para pausar.');
      return;
    }

    if (_state.paused) {
      _setStatus('A gravação já está pausada.');
      return;
    }

    _setState(
      _state.copyWith(processing: true, statusMessage: 'Pausando gravação...'),
    );
    try {
      await _recordingService.pauseRecording();
    } catch (e) {
      if (_isMicrophonePermissionError(e)) {
        await _handleMicrophonePermissionLost(
          reason: 'microphone_permission_lost_during_pause',
          error: e,
        );
        return;
      }
      rethrow;
    }
    _stopSilenceMonitoring();
    unawaited(_shadowRouter.stop());
    _setState(
      _state.copyWith(
        paused: true,
        processing: false,
        silenceMs: 0,
        statusMessage: 'Gravação pausada.',
      ),
    );
    onHistory('Pausou gravação', 'gravacao_pausada');
  }

  Future<void> resumeRecording({
    required RecordingFinalizer finalizeRecording,
    required RecordingHistoryWriter onHistory,
    Future<void> Function()? onAutomaticStop,
  }) async {
    if (!_state.recording || !_state.paused) {
      _setStatus('Não existe gravação pausada para retomar.');
      return;
    }

    _setState(
      _state.copyWith(processing: true, statusMessage: 'Retomando gravação...'),
    );
    if (_captureClosedByLifecycle) {
      _setState(
        _state.copyWith(
          processing: false,
          statusMessage:
              'Gravação pausada por interrupção do sistema. Encerre e salve antes de continuar.',
        ),
      );
      return;
    }

    try {
      await _recordingService.resumeRecording();
    } catch (e) {
      if (_isMicrophonePermissionError(e)) {
        await _handleMicrophonePermissionLost(
          reason: 'microphone_permission_lost_during_resume',
          error: e,
        );
        return;
      }
      rethrow;
    }
    _shadowRouter.start(
      _recordingService.rawAudioChunks,
      correlationId:
          'recording_shadow_${DateTime.now().microsecondsSinceEpoch}',
    );
    _setState(
      _state.copyWith(
        paused: false,
        processing: false,
        silenceMs: 0,
        statusMessage: 'Gravação retomada.',
      ),
    );
    _startSilenceMonitoring(finalizeRecording, onHistory, onAutomaticStop);
    onHistory('Retomou gravação', 'gravacao_retomada');
  }

  Future<Gravacao?> stopRecording({
    required RecordingFinalizer finalizeRecording,
    required void Function(
      String action,
      String type, {
      int? recordingId,
      int? projectId,
    })
    onHistory,
    bool automatic = false,
  }) async {
    if (_isStopping || !_state.recording) {
      _setStatus('Não existe gravação em andamento para encerrar.');
      return null;
    }
    _isStopping = true;

    _stopSilenceMonitoring();
    _setState(
      _state.copyWith(processing: true, statusMessage: 'Salvando gravação...'),
    );

    try {
      final completedPath = _captureClosedByLifecycle
          ? _state.currentPath
          : await _recordingService.stopRecording();
      _captureClosedByLifecycle = false;
      final startedAt = _state.startedAt;
      if (completedPath == null || completedPath.isEmpty || startedAt == null) {
        _sessionManager.registerFailure(
          ownerId: ownerId,
          reason: 'recording_save_failed',
          message: 'Falha ao salvar gravação.',
        );
        _resetAfterRecording('Não foi possível salvar a gravação.');
        return null;
      }

      final saved = await finalizeRecording(
        path: completedPath,
        startedAt: startedAt,
        automatic: automatic,
      );
      _resetAfterRecording(
        automatic
            ? '${saved.nome} salva automaticamente após silêncio.'
            : '${saved.nome} salva no projeto.',
      );
      onHistory(
        automatic
            ? 'Encerrou gravação por silêncio'
            : 'Encerrou gravação real e criou ${saved.nome}',
        automatic ? 'gravacao_finalizada_por_silencio' : 'gravacao_finalizada',
        recordingId: saved.id,
        projectId: saved.projetoId,
      );
      return saved;
    } catch (e) {
      if (_isMicrophonePermissionError(e)) {
        await _handleMicrophonePermissionLost(
          reason: 'microphone_permission_lost_during_stop',
          error: e,
        );
        return null;
      }
      _sessionManager.registerFailure(
        ownerId: ownerId,
        reason: 'recording_stop_failed',
        message: UserFacingMessages.recordingSaveError,
      );
      _resetAfterRecording(UserFacingMessages.recordingSaveError);
      rethrow;
    } finally {
      _isStopping = false;
    }
  }

  Future<void> play({
    required String path,
    required String name,
    required String emptyPathMessage,
    required String recordingActiveMessage,
    required void Function() onHistory,
  }) async {
    if (path.isEmpty) {
      _setStatus(emptyPathMessage);
      return;
    }

    if (_state.recording) {
      _setStatus(recordingActiveMessage);
      return;
    }

    _setState(
      _state.copyWith(
        processing: true,
        statusMessage: 'Preparando reprodução...',
      ),
    );

    try {
      _resetTimelineProgress();
      await _playerService.play(path);
      _setState(
        _state.copyWith(
          playing: true,
          processing: false,
          timelineProgress: 0.0,
          statusMessage: 'Reproduzindo $name.',
        ),
      );
      onHistory();
    } catch (e) {
      _setState(
        _state.copyWith(
          playing: false,
          processing: false,
          timelineProgress: 0.0,
          statusMessage: UserFacingMessages.playbackError,
        ),
      );
    }
  }

  Future<void> stopPlayback() async {
    await _playerService.stop();
    _playbackDuration = null;
    _setState(
      _state.copyWith(
        playing: false,
        timelineProgress: 0.0,
        statusMessage: 'Reprodução parada.',
      ),
    );
  }

  void _startSilenceMonitoring(
    RecordingFinalizer finalizeRecording,
    RecordingHistoryWriter onHistory,
    Future<void> Function()? onAutomaticStop,
  ) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(
      const Duration(milliseconds: silenceMonitorIntervalMs),
      (timer) async {
        if (!_state.recording || _state.paused || _state.processing) {
          return;
        }

        if (!_automaticSilenceStop) {
          return;
        }

        try {
          final amplitude = await _recordingService.getAmplitude();
          final level = amplitude.current;
          final nextSilence = level <= _silenceThresholdDb
              ? _state.silenceMs + silenceMonitorIntervalMs
              : 0;
          _setState(
            _state.copyWith(currentAmplitude: level, silenceMs: nextSilence),
          );

          if (nextSilence >= _silenceLimitMs) {
            timer.cancel();
            _sessionManager.diagnostics.eventBus.publish(
              SilenceDetectedEvent(
                source: 'recording_realtime_coordinator',
                ownerId: ownerId,
                reason: 'automatic_silence_stop',
                silenceMs: nextSilence,
                level: level,
              ),
            );
            _sessionManager.diagnostics.record(
              VoiceDiagnosticEventType.recordingStopped,
              ownerId: ownerId,
              reason: 'automatic_silence_stop',
              message: 'Parada automática por silêncio acionada.',
              metadata: {'silenceMs': nextSilence, 'level': level},
            );
            await stopRecording(
              finalizeRecording: finalizeRecording,
              onHistory: onHistory,
              automatic: true,
            );
            await onAutomaticStop?.call();
          }
        } catch (e) {
          if (_isMicrophonePermissionError(e)) {
            await _handleMicrophonePermissionLost(
              reason: 'microphone_permission_lost_during_monitoring',
              error: e,
            );
            return;
          }
          _sessionManager.diagnostics.record(
            VoiceDiagnosticEventType.error,
            ownerId: ownerId,
            reason: 'silence_monitor_failed',
            message: 'Erro ao monitorar silencio: $e',
          );
        }
      },
    );
  }

  void _stopSilenceMonitoring() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _resetAfterRecording(String statusMessage) {
    _stopSilenceMonitoring();
    _stopRecordingProgressTimer();
    _clearLifecyclePauseFlags();
    _setState(
      _state.copyWith(
        recording: false,
        paused: false,
        processing: false,
        clearCurrentPath: true,
        clearStartedAt: true,
        silenceMs: 0,
        currentAmplitude: -160.0,
        timelineProgress: 0.0,
        statusMessage: statusMessage,
      ),
    );
  }

  void _startRecordingProgressTimer() {
    _stopRecordingProgressTimer();
    _recordingProgressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateRecordingProgress(),
    );
  }

  void _stopRecordingProgressTimer() {
    _recordingProgressTimer?.cancel();
    _recordingProgressTimer = null;
  }

  void _handleLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_pauseForLifecycle(state));
      case AppLifecycleState.resumed:
        _handleLifecycleResumed();
      case AppLifecycleState.detached:
        unawaited(_safeTeardownForDetached());
    }
  }

  @visibleForTesting
  Future<void> handleLifecycleStateForTesting(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        await _pauseForLifecycle(state);
      case AppLifecycleState.resumed:
        _handleLifecycleResumed();
      case AppLifecycleState.detached:
        await _safeTeardownForDetached();
    }
  }

  Future<void> _pauseForLifecycle(AppLifecycleState state) async {
    if (_disposed || _handlingLifecycle || _pausedByLifecycle) {
      return;
    }
    _handlingLifecycle = true;
    try {
      _wasRecordingBeforeLifecyclePause = _state.recording && !_state.paused;
      _wasSttActiveBeforeLifecyclePause = _sessionManager.listeningActive;
      if (!_wasRecordingBeforeLifecyclePause &&
          !_wasSttActiveBeforeLifecyclePause) {
        return;
      }

      _pausedByLifecycle = true;
      if (_wasSttActiveBeforeLifecyclePause) {
        await _sessionManager.cancelListening(
          ownerId: _sessionManager.activeOwnerId,
          reason: 'lifecycle_${state.name}',
        );
      }

      if (_wasRecordingBeforeLifecyclePause) {
        await _closeActiveCaptureForLifecycle(state);
      }

      _publishLifecyclePauseTelemetry(state);
    } finally {
      _handlingLifecycle = false;
    }
  }

  Future<void> _closeActiveCaptureForLifecycle(AppLifecycleState state) async {
    _stopSilenceMonitoring();
    _stopRecordingProgressTimer();
    await _safeStopShadowRouter();
    _setState(
      _state.copyWith(
        processing: true,
        statusMessage: 'Interrupcao do sistema detectada. Salvando buffer...',
      ),
    );

    try {
      final completedPath = await _recordingService.stopRecording();
      final safePath = completedPath != null && completedPath.isNotEmpty
          ? completedPath
          : _state.currentPath;
      _captureClosedByLifecycle = safePath != null && safePath.isNotEmpty;
      _setState(
        _state.copyWith(
          recording: true,
          paused: true,
          processing: false,
          currentPath: safePath,
          silenceMs: 0,
          statusMessage:
              'Gravação pausada por interrupção do sistema. Encerre e salve para continuar.',
        ),
      );
    } catch (e) {
      await _handleMicrophonePermissionLost(
        reason: 'microphone_permission_lost_during_lifecycle_${state.name}',
        error: e,
      );
    }
  }

  void _handleLifecycleResumed() {
    if (!_pausedByLifecycle) {
      return;
    }
    _publishLifecycleResumeTelemetry();
    _setState(
      _state.copyWith(
        processing: false,
        statusMessage:
            'Gravação pausada por interrupção do sistema. Escolha a próxima ação.',
      ),
    );
  }

  Future<void> _safeTeardownForDetached() async {
    if (_disposed) {
      return;
    }
    await _safeStopShadowRouter();
    _stopSilenceMonitoring();
    _stopRecordingProgressTimer();
    await _realtimeShutdown('app_detached');
    dispose();
  }

  Future<bool> _checkMicrophonePermissionBeforeCapture() async {
    try {
      return _recordingService.hasPermission();
    } catch (e) {
      if (_isMicrophonePermissionError(e)) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _handleMicrophonePermissionLost({
    required String reason,
    required Object error,
  }) async {
    _stopSilenceMonitoring();
    _stopRecordingProgressTimer();
    await _safeStopShadowRouter();
    if (_state.recording && !_captureClosedByLifecycle) {
      try {
        final completedPath = await _recordingService.stopRecording();
        if (completedPath != null && completedPath.isNotEmpty) {
          _captureClosedByLifecycle = true;
          _setState(_state.copyWith(currentPath: completedPath));
        }
      } catch (_) {
        // Best-effort: keep UI/runtime stable after abrupt permission loss.
      }
    }
    _publishMicrophonePermissionLost(reason: reason, error: error);
    _sessionManager.exitRecordingMode(
      ownerId: ownerId,
      reason: 'microphone_permission_lost',
    );
    _setState(
      _state.copyWith(
        recording: _state.currentPath != null,
        paused: true,
        processing: false,
        silenceMs: 0,
        statusMessage:
            'Permissão do microfone removida. Encerre e salve o áudio parcial ou reative a permissão.',
      ),
    );
  }

  Future<void> _safeStopShadowRouter() async {
    try {
      await _shadowRouter.stop();
    } catch (_) {
      // Best-effort cleanup during OS interruption.
    }
  }

  bool _isMicrophonePermissionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission') ||
        text.contains('permiss') ||
        text.contains('denied') ||
        text.contains('microphone') ||
        text.contains('record_audio');
  }

  void _publishMicrophonePermissionLost({
    required String reason,
    Object? error,
  }) {
    _sessionManager.diagnostics.eventBus.publish(
      VoiceCommandFailedEvent(
        source: 'recording_realtime_coordinator',
        reason: reason,
        ownerId: ownerId,
        metadata: {
          'message': 'Permissão do microfone removida.',
          if (error != null) 'error': error.toString(),
        },
      ),
    );
    _sessionManager.diagnostics.eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'recording_realtime_coordinator',
        reason: reason,
        ownerId: ownerId,
        metadata: {
          'message': 'Permissão do microfone removida.',
          if (error != null) 'error': error.toString(),
        },
      ),
    );
  }

  void _publishLifecyclePauseTelemetry(AppLifecycleState state) {
    _sessionManager.diagnostics.eventBus.publish(
      VoiceStateChangedEvent(
        source: 'recording_realtime_coordinator',
        previousState: _wasRecordingBeforeLifecyclePause
            ? 'recording'
            : 'listening',
        nextState: 'pausedByLifecycle',
        reason: 'recording_paused_by_lifecycle_${state.name}',
        ownerId: ownerId,
        metadata: {
          'wasRecording': _wasRecordingBeforeLifecyclePause,
          'wasSttActive': _wasSttActiveBeforeLifecyclePause,
          'captureClosed': _captureClosedByLifecycle,
        },
      ),
    );
  }

  void _publishLifecycleResumeTelemetry() {
    _sessionManager.diagnostics.eventBus.publish(
      VoiceStateChangedEvent(
        source: 'recording_realtime_coordinator',
        previousState: 'pausedByLifecycle',
        nextState: 'userActionRequired',
        reason: 'recording_resume_requires_user_action',
        ownerId: ownerId,
        metadata: {
          'wasRecording': _wasRecordingBeforeLifecyclePause,
          'wasSttActive': _wasSttActiveBeforeLifecyclePause,
          'captureClosed': _captureClosedByLifecycle,
        },
      ),
    );
  }

  void _clearLifecyclePauseFlags() {
    _wasRecordingBeforeLifecyclePause = false;
    _wasSttActiveBeforeLifecyclePause = false;
    _pausedByLifecycle = false;
    _captureClosedByLifecycle = false;
  }

  void _updateRecordingProgress() {
    if (!_state.recording || _state.paused || _state.processing) {
      return;
    }

    final startedAt = _state.startedAt;
    if (startedAt == null) {
      _resetTimelineProgress();
      return;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final nextProgress =
        elapsed.inMilliseconds /
        (recordingTimelineFallbackSeconds * Duration.millisecondsPerSecond);
    _setTimelineProgress(nextProgress);
  }

  void _handlePlaybackPosition(Duration position) {
    if (!_state.playing || _state.processing) {
      return;
    }

    final duration = _playbackDuration;
    if (duration == null || duration.inMilliseconds <= 0) {
      final fallbackProgress = position.inMilliseconds / (30 * 1000);
      _setTimelineProgress(fallbackProgress);
      return;
    }

    _setTimelineProgress(position.inMilliseconds / duration.inMilliseconds);
  }

  void _setTimelineProgress(double rawProgress) {
    final nextProgress = _sanitizeProgress(rawProgress);
    final currentProgress = _state.timelineProgress;
    if (nextProgress < currentProgress &&
        currentProgress - nextProgress < 0.02) {
      return;
    }
    if ((nextProgress - currentProgress).abs() < 0.001) {
      return;
    }

    _setState(_state.copyWith(timelineProgress: nextProgress));
  }

  void _resetTimelineProgress() {
    if (_state.timelineProgress == 0.0) {
      return;
    }
    _setState(_state.copyWith(timelineProgress: 0.0));
  }

  double _sanitizeProgress(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  void _setStatus(String message) {
    _setState(_state.copyWith(statusMessage: message));
  }

  void _setState(RecordingRealtimeState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _stopSilenceMonitoring();
    _stopRecordingProgressTimer();
    unawaited(_shadowRouter.dispose());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_playbackPositionSubscription?.cancel());
    unawaited(_playbackDurationSubscription?.cancel());
    unawaited(_recordingService.dispose());
    unawaited(_playerService.dispose());
    super.dispose();
  }
}
