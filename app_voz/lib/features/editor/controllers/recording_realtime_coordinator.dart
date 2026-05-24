import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/gravacao.dart';
import '../../voices/coordination/voice_diagnostics.dart';
import '../../voices/coordination/voice_session_manager.dart';
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
      statusMessage: statusMessage ?? this.statusMessage,
    );
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
    bool automaticSilenceStop = true,
  }) : _recordingService = recordingService ?? _createRecordingService(ownerId),
       _playerService = playerService ?? AudioPlayerService(ownerId: ownerId),
       _shadowRouter = shadowRouter ?? AudioStreamShadowRouter(),
       _sessionManager = sessionManager ?? VoiceSessionManager.instance,
       _silenceLimitMs = silenceLimitMs,
       _automaticSilenceStop = automaticSilenceStop {
    _playerStateSubscription = _playerService.playerStateStream.listen((state) {
      if (!state.playing && _state.playing) {
        _setState(
          _state.copyWith(
            playing: false,
            statusMessage: 'Reproducao finalizada.',
          ),
        );
      }
    });
  }

  static const int silenceMonitorIntervalMs = 500;
  static const double silenceThresholdDb = -36.0;
  static const bool _useStreamFirstMode = bool.fromEnvironment(
    'USE_STREAM_FIRST_AUDIO',
    defaultValue: false,
  );

  final AudioRecordingCapture _recordingService;
  final AudioPlayerService _playerService;
  final AudioStreamShadowRouter _shadowRouter;
  final VoiceSessionManager _sessionManager;
  final String ownerId;

  StreamSubscription? _playerStateSubscription;
  Timer? _silenceTimer;
  int _silenceLimitMs;
  bool _automaticSilenceStop;

  RecordingRealtimeState _state = const RecordingRealtimeState();

  RecordingRealtimeState get state => _state;

  Stream<Uint8List> get rawAudioChunks => _recordingService.rawAudioChunks;

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
  }) {
    _automaticSilenceStop = automaticSilenceStop;
    _silenceLimitMs = silenceLimitMs;
  }

  Future<void> startRecording({
    required RecordingFinalizer finalizeRecording,
    required RecordingHistoryWriter onHistory,
    Future<void> Function()? onAutomaticStop,
  }) async {
    if (_state.recording) {
      _setStatus('Ja existe uma gravacao em andamento.');
      return;
    }

    if (_state.processing) {
      _setStatus('Aguarde o processamento atual terminar.');
      return;
    }

    if (_state.playing) {
      await stopPlayback();
    }

    _sessionManager.diagnostics.record(
      VoiceDiagnosticEventType.recordingStarted,
      ownerId: ownerId,
      reason: 'recording_intent',
      message: 'Intencao de iniciar gravacao recebida.',
    );
    _setState(
      _state.copyWith(
        processing: true,
        statusMessage: 'Preparando gravacao...',
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
          statusMessage: 'Gravacao real iniciada.',
        ),
      );
      _startSilenceMonitoring(finalizeRecording, onHistory, onAutomaticStop);
      onHistory('Iniciou gravacao real', 'gravacao_iniciada');
    } catch (e) {
      _sessionManager.registerFailure(
        ownerId: ownerId,
        reason: 'recording_start_failed',
        message: 'Erro ao iniciar gravacao: $e',
      );
      _setState(
        _state.copyWith(
          processing: false,
          statusMessage: 'Erro ao iniciar gravacao: $e',
        ),
      );
      rethrow;
    }
  }

  Future<void> pauseRecording({
    required void Function(String action, String type) onHistory,
  }) async {
    if (!_state.recording) {
      _setStatus('Nao existe gravacao em andamento para pausar.');
      return;
    }

    if (_state.paused) {
      _setStatus('A gravacao ja esta pausada.');
      return;
    }

    _setState(
      _state.copyWith(processing: true, statusMessage: 'Pausando gravacao...'),
    );
    await _recordingService.pauseRecording();
    _stopSilenceMonitoring();
    unawaited(_shadowRouter.stop());
    _setState(
      _state.copyWith(
        paused: true,
        processing: false,
        silenceMs: 0,
        statusMessage: 'Gravacao pausada.',
      ),
    );
    onHistory('Pausou gravacao', 'gravacao_pausada');
  }

  Future<void> resumeRecording({
    required RecordingFinalizer finalizeRecording,
    required RecordingHistoryWriter onHistory,
    Future<void> Function()? onAutomaticStop,
  }) async {
    if (!_state.recording || !_state.paused) {
      _setStatus('Nao existe gravacao pausada para retomar.');
      return;
    }

    _setState(
      _state.copyWith(processing: true, statusMessage: 'Retomando gravacao...'),
    );
    await _recordingService.resumeRecording();
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
        statusMessage: 'Gravacao retomada.',
      ),
    );
    _startSilenceMonitoring(finalizeRecording, onHistory, onAutomaticStop);
    onHistory('Retomou gravacao', 'gravacao_retomada');
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
    if (!_state.recording) {
      _setStatus('Nao existe gravacao em andamento para encerrar.');
      return null;
    }

    _stopSilenceMonitoring();
    _setState(
      _state.copyWith(processing: true, statusMessage: 'Salvando gravacao...'),
    );

    try {
      final completedPath = await _recordingService.stopRecording();
      final startedAt = _state.startedAt;
      if (completedPath == null || completedPath.isEmpty || startedAt == null) {
        _sessionManager.registerFailure(
          ownerId: ownerId,
          reason: 'recording_save_failed',
          message: 'Falha ao salvar gravacao.',
        );
        _resetAfterRecording('Nao foi possivel salvar a gravacao.');
        return null;
      }

      final saved = await finalizeRecording(
        path: completedPath,
        startedAt: startedAt,
        automatic: automatic,
      );
      _resetAfterRecording(
        automatic
            ? '${saved.nome} salva automaticamente apos silencio.'
            : '${saved.nome} salva no projeto.',
      );
      onHistory(
        automatic
            ? 'Encerrou gravacao por silencio'
            : 'Encerrou gravacao real e criou ${saved.nome}',
        automatic ? 'gravacao_finalizada_por_silencio' : 'gravacao_finalizada',
        recordingId: saved.id,
        projectId: saved.projetoId,
      );
      return saved;
    } catch (e) {
      _sessionManager.registerFailure(
        ownerId: ownerId,
        reason: 'recording_stop_failed',
        message: 'Erro ao encerrar gravacao: $e',
      );
      _resetAfterRecording('Erro ao encerrar gravacao: $e');
      rethrow;
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
        statusMessage: 'Preparando reproducao...',
      ),
    );

    try {
      await _playerService.play(path);
      _setState(
        _state.copyWith(
          playing: true,
          processing: false,
          statusMessage: 'Reproduzindo $name.',
        ),
      );
      onHistory();
    } catch (e) {
      _setState(
        _state.copyWith(
          playing: false,
          processing: false,
          statusMessage: 'Erro ao reproduzir audio: $e',
        ),
      );
    }
  }

  Future<void> stopPlayback() async {
    await _playerService.stop();
    _setState(
      _state.copyWith(playing: false, statusMessage: 'Reproducao parada.'),
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
          final nextSilence = level <= silenceThresholdDb
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
              message: 'Parada automatica por silencio acionada.',
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
    _setState(
      _state.copyWith(
        recording: false,
        paused: false,
        processing: false,
        clearCurrentPath: true,
        clearStartedAt: true,
        silenceMs: 0,
        currentAmplitude: -160.0,
        statusMessage: statusMessage,
      ),
    );
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
    _stopSilenceMonitoring();
    unawaited(_shadowRouter.dispose());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_recordingService.dispose());
    unawaited(_playerService.dispose());
    super.dispose();
  }
}
