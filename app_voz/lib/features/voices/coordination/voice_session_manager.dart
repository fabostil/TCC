import 'dart:async';

import 'package:flutter/foundation.dart';

import '../realtime/runtime/voice_realtime_ecosystem.dart';
import '../realtime/runtime/runtime_engine.dart';
import '../realtime/runtime/runtime_registry.dart';
import '../realtime/dispatch/contratos/audio_output_guard.dart';
import '../realtime/voice_realtime_events.dart';
import '../services/speech_service.dart';
import 'voice_diagnostics.dart';
import 'voice_state_machine.dart';

enum VoiceAudioOwnerType { none, stt, recorder, playback }

enum VoiceRecoveryReason {
  normal,
  afterError,
  afterRouteChange,
  afterRecording,
}

class VoiceSessionManager extends ChangeNotifier implements AudioOutputGuard {
  VoiceSessionManager._({
    SpeechService? speechService,
    VoiceStateMachine? stateMachine,
  }) : speech = speechService ?? SpeechService.instance,
       stateMachine = stateMachine ?? VoiceStateMachine() {
    VoiceRealtimeEcosystem.instance.startUnawaited();
    _controlSubscription = this.stateMachine.diagnostics.eventBus
        .on<StopVoiceCaptureRequestedEvent>()
        .listen(_handleStopVoiceCaptureRequested);
  }

  static final VoiceSessionManager instance = VoiceSessionManager._();

  @visibleForTesting
  factory VoiceSessionManager.forTesting({
    SpeechService? speechService,
    VoiceStateMachine? stateMachine,
  }) {
    return VoiceSessionManager._(
      speechService: speechService,
      stateMachine: stateMachine,
    );
  }

  static const Duration restartDelayDefault = Duration(milliseconds: 700);
  static const Duration restartDelayAfterError = Duration(seconds: 2);
  static const int maxRecoveryAttempts = 3;
  static const Duration busyCooldown = Duration(seconds: 3);

  final SpeechService speech;
  final VoiceStateMachine stateMachine;

  String? _activeOwnerId;
  VoiceAudioOwnerType _audioOwnerType = VoiceAudioOwnerType.none;
  int _generation = 0;
  String? _activeRecoveryCorrelationId;
  String? _activeListeningCorrelationId;
  String? _lastFailureReason;
  DateTime? _busyCooldownUntil;
  late final StreamSubscription<StopVoiceCaptureRequestedEvent>
  _controlSubscription;
  bool _speechHardwareStarted = false;
  bool _listeningStartInProgress = false;

  VoiceDiagnostics get diagnostics => stateMachine.diagnostics;

  String? get activeOwnerId => _activeOwnerId;

  VoiceAudioOwnerType get audioOwnerType => _audioOwnerType;

  bool get recordingActive => _audioOwnerType == VoiceAudioOwnerType.recorder;

  bool get playbackActive => _audioOwnerType == VoiceAudioOwnerType.playback;

  bool get listeningActive => _audioOwnerType == VoiceAudioOwnerType.stt;

  bool get isSpeechListening => speech.isListening;

  String? get lastFailureReason => _lastFailureReason;

  bool get isListeningStartInProgress => _listeningStartInProgress;

  bool get isBusyCooldownActive {
    final cooldownUntil = _busyCooldownUntil;
    return cooldownUntil != null && DateTime.now().isBefore(cooldownUntil);
  }

  bool get hasPendingRecovery => _activeRecoveryCorrelationId != null;

  int get recoveryAttempts => stateMachine.snapshot.recoveryAttempts;

  @override
  bool isAudioOutputAvailable() {
    return _audioOwnerType == VoiceAudioOwnerType.none ||
        _audioOwnerType == VoiceAudioOwnerType.playback;
  }

  Duration restartDelayFor(VoiceRecoveryReason reason) {
    if (_lastFailureReason == 'error_busy') {
      return busyCooldown + const Duration(milliseconds: 500);
    }
    return reason == VoiceRecoveryReason.afterError
        ? restartDelayAfterError
        : restartDelayDefault;
  }

  bool canClaimListening(String ownerId) {
    if (_audioOwnerType == VoiceAudioOwnerType.recorder) {
      diagnostics.record(
        VoiceDiagnosticEventType.microphoneConflict,
        ownerId: ownerId,
        reason: 'recording_active',
        message: 'STT bloqueado: microfone reservado para gravacao.',
      );
      diagnostics.eventBus.publish(
        MicrophoneConflictDetectedEvent(
          source: 'voice_session_manager',
          ownerId: ownerId,
          reason: 'recording_active',
          conflict: 'recorder_blocks_stt',
          message: 'STT bloqueado: microfone reservado para gravacao.',
        ),
      );
      return false;
    }

    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      diagnostics.record(
        VoiceDiagnosticEventType.microphoneConflict,
        ownerId: ownerId,
        reason: 'owner_conflict',
        message: 'STT bloqueado: $_activeOwnerId ja possui a sessao.',
      );
      diagnostics.eventBus.publish(
        MicrophoneConflictDetectedEvent(
          source: 'voice_session_manager',
          ownerId: ownerId,
          reason: 'owner_conflict',
          conflict: '$_activeOwnerId owns session',
          message: 'STT bloqueado: $_activeOwnerId ja possui a sessao.',
        ),
      );
      return false;
    }

    return true;
  }

  bool claimListening(String ownerId) {
    if (!canClaimListening(ownerId)) {
      return false;
    }

    if (stateMachine.state == VoiceState.disabled) {
      stateMachine.transitionTo(
        VoiceState.idle,
        ownerId: ownerId,
        reason: 'voice_enabled',
        force: true,
      );
    }

    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = ownerId;
    _audioOwnerType = VoiceAudioOwnerType.stt;
    VoiceRuntimeRegistry.instance.setActiveOwner(ownerId);
    stateMachine.transitionTo(
      VoiceState.listening,
      ownerId: ownerId,
      message: 'Sessao de escuta reservada.',
      reason: 'claim_listening',
    );
    diagnostics.record(
      VoiceDiagnosticEventType.listeningStarted,
      ownerId: ownerId,
      message: 'Owner reservou a escuta.',
    );
    _publishAudioOwnershipChanged(
      previousOwnerType,
      VoiceAudioOwnerType.stt,
      ownerId: ownerId,
      reason: 'claim_listening',
    );
    notifyListeners();
    return true;
  }

  void releaseOwner(String ownerId) {
    if (_activeOwnerId != ownerId) {
      return;
    }

    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    diagnostics.record(
      VoiceDiagnosticEventType.listeningStopped,
      ownerId: ownerId,
      reason: 'owner_released',
      message: 'Owner liberou a escuta.',
    );
    if (stateMachine.state == VoiceState.listening) {
      stateMachine.transitionTo(
        VoiceState.idle,
        ownerId: ownerId,
        reason: 'owner_released',
      );
    }
    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: ownerId,
      reason: 'owner_released',
    );
    _publishSpeechStopped(ownerId: ownerId, reason: 'owner_released');
    notifyListeners();
  }

  Future<bool> startListening({
    required String ownerId,
    required void Function(String text) onResult,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    if (_listeningStartInProgress) {
      _recordStartSkipped(
        ownerId: ownerId,
        reason: 'start_in_progress',
        message: 'Start ignorado: inicio de STT ja esta em andamento.',
      );
      return false;
    }

    if (_activeOwnerId == ownerId &&
        _audioOwnerType == VoiceAudioOwnerType.stt) {
      _recordStartSkipped(
        ownerId: ownerId,
        reason: 'already_listening',
        message: 'Start ignorado: owner ja possui escuta ativa.',
      );
      return false;
    }

    final busyCooldownUntil = _busyCooldownUntil;
    if (busyCooldownUntil != null &&
        DateTime.now().isBefore(busyCooldownUntil)) {
      _recordStartSkipped(
        ownerId: ownerId,
        reason: 'busy_cooldown',
        message: 'Start ignorado: aguardando Android liberar o STT.',
      );
      return false;
    }

    invalidateRecovery();
    final listeningGeneration = _generation;

    if (!claimListening(ownerId)) {
      return false;
    }

    _activeListeningCorrelationId = 'stt_${ownerId}_$_generation';
    _speechHardwareStarted = false;
    _listeningStartInProgress = true;
    final bool started;
    try {
      started = await speech.startListening(
        onResult: (text) {
          if (listeningGeneration != _generation) {
            diagnostics.record(
              VoiceDiagnosticEventType.recoverySkipped,
              ownerId: ownerId,
              reason: 'stale_result',
              message: 'Resultado STT antigo ignorado apos reset de sessao.',
            );
            return;
          }
          diagnostics.eventBus.publish(
            SpeechResultReceivedEvent(
              source: 'voice_session_manager',
              ownerId: ownerId,
              reason: 'speech_result',
              correlationId: _activeListeningCorrelationId,
              text: text,
            ),
          );
          onResult(text);
        },
        onStatus: (status) {
          if (listeningGeneration != _generation) {
            diagnostics.record(
              VoiceDiagnosticEventType.recoverySkipped,
              ownerId: ownerId,
              reason: 'stale_status_$status',
              message: 'Status STT antigo ignorado apos reset de sessao.',
            );
            return;
          }
          diagnostics.record(
            VoiceDiagnosticEventType.listeningStarted,
            ownerId: ownerId,
            reason: status,
            message: 'Status STT: $status.',
          );
          if (status == 'done' || status == 'notListening') {
            _releaseStoppedSpeech(ownerId: ownerId, reason: status);
          }
          onStatus?.call(status);
        },
        onError: (error) {
          if (listeningGeneration != _generation) {
            diagnostics.record(
              VoiceDiagnosticEventType.recoverySkipped,
              ownerId: ownerId,
              reason: 'stale_error_$error',
              message: 'Erro STT antigo ignorado apos reset de sessao.',
            );
            return;
          }
          if (error == 'error_busy') {
            _busyCooldownUntil = DateTime.now().add(busyCooldown);
          }
          registerFailure(
            ownerId: ownerId,
            reason: error,
            message: 'Não foi possível reconhecer a fala.',
          );
          _releaseStoppedSpeech(ownerId: ownerId, reason: error);
          onError?.call(error);
        },
      );
    } finally {
      _listeningStartInProgress = false;
    }

    if (listeningGeneration != _generation) {
      _releaseStoppedSpeech(ownerId: ownerId, reason: 'stale_start_result');
      return false;
    }

    if (!started) {
      registerFailure(
        ownerId: ownerId,
        reason: 'start_failed',
        message: 'Não foi possível iniciar a escuta de voz.',
      );
      releaseOwner(ownerId);
      return false;
    }

    _speechHardwareStarted = true;
    _busyCooldownUntil = null;
    diagnostics.eventBus.publish(
      SpeechListeningStartedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: 'speech_started',
        correlationId: _activeListeningCorrelationId,
      ),
    );
    stateMachine.resetRecoveryAttempts();
    return true;
  }

  Future<void> forceResetListeningSession({
    String? ownerId,
    required String reason,
    bool clearBusyCooldown = false,
  }) async {
    final releasedOwner = ownerId ?? _activeOwnerId;
    final previousOwnerType = _audioOwnerType;
    invalidateRecovery();

    if (clearBusyCooldown) {
      _busyCooldownUntil = null;
    }
    _listeningStartInProgress = false;

    try {
      await speech.cancelListening();
    } catch (error) {
      diagnostics.record(
        VoiceDiagnosticEventType.error,
        ownerId: releasedOwner,
        reason: 'reset_cancel_failed',
        message: 'Falha ao cancelar sessao STT anterior durante reset manual.',
        metadata: {'error': error.runtimeType.toString()},
      );
    }

    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    _speechHardwareStarted = false;
    _activeListeningCorrelationId = null;
    _lastFailureReason = null;

    diagnostics.record(
      VoiceDiagnosticEventType.listeningStopped,
      ownerId: releasedOwner,
      reason: reason,
      message: 'Sessao de escuta reiniciada manualmente.',
    );
    _publishSpeechStopped(ownerId: releasedOwner, reason: reason);

    if (stateMachine.state != VoiceState.recording &&
        stateMachine.state != VoiceState.disabled) {
      stateMachine.transitionTo(
        VoiceState.idle,
        ownerId: releasedOwner,
        reason: reason,
        force: true,
      );
    }

    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: releasedOwner,
      reason: reason,
    );
    notifyListeners();
  }

  void cancelPendingRecovery({String? ownerId, required String reason}) {
    if (_activeRecoveryCorrelationId == null) {
      return;
    }
    final correlationId = _activeRecoveryCorrelationId;
    invalidateRecovery();
    diagnostics.record(
      VoiceDiagnosticEventType.recoverySkipped,
      ownerId: ownerId,
      reason: reason,
      message: 'Recovery pendente cancelado: $correlationId.',
    );
  }

  Future<void> stopListening(String ownerId, {bool manual = false}) async {
    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      diagnostics.record(
        VoiceDiagnosticEventType.recoverySkipped,
        ownerId: ownerId,
        reason: 'stop_owner_mismatch',
        message: 'Stop ignorado: $_activeOwnerId possui a escuta ativa.',
      );
      return;
    }

    invalidateRecovery();
    await speech.stopListening();
    diagnostics.record(
      VoiceDiagnosticEventType.listeningStopped,
      ownerId: ownerId,
      reason: manual ? 'manual_stop' : 'stop',
      message: 'Escuta STT parada.',
    );
    _publishSpeechStopped(
      ownerId: ownerId,
      reason: manual ? 'manual_stop' : 'stop',
    );
    releaseOwner(ownerId);
    stateMachine.transitionTo(
      manual ? VoiceState.paused : VoiceState.idle,
      ownerId: ownerId,
      reason: manual ? 'manual_stop' : 'stop',
    );
  }

  Future<void> cancelListening({
    String? ownerId,
    String reason = 'cancel',
  }) async {
    if (ownerId != null &&
        _activeOwnerId != null &&
        _activeOwnerId != ownerId) {
      diagnostics.record(
        VoiceDiagnosticEventType.recoverySkipped,
        ownerId: ownerId,
        reason: 'cancel_owner_mismatch',
        message: 'Cancel ignorado: $_activeOwnerId possui a escuta ativa.',
      );
      return;
    }

    invalidateRecovery();
    await speech.cancelListening();
    final releasedOwner = ownerId ?? _activeOwnerId;
    diagnostics.record(
      VoiceDiagnosticEventType.listeningStopped,
      ownerId: releasedOwner,
      reason: reason,
      message: 'Escuta STT cancelada.',
    );
    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    if (stateMachine.state != VoiceState.recording &&
        stateMachine.state != VoiceState.disabled) {
      stateMachine.transitionTo(
        VoiceState.idle,
        ownerId: releasedOwner,
        reason: reason,
      );
    }
    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: releasedOwner,
      reason: reason,
    );
    _publishSpeechStopped(ownerId: releasedOwner, reason: reason);
    notifyListeners();
  }

  Future<void> prepareForNavigation() {
    return cancelListening(reason: 'navigation');
  }

  void onRouteDidPush() {
    invalidateRecovery();
    unawaited(cancelListening(reason: 'route_push'));
  }

  void onRouteDidPop() {
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      // Libera ownership do STT sincronamente para que a tela anterior
      // possa reivindicar imediatamente em didPopNext, sem esperar pelo
      // dispose da tela filha (que ocorre só após a animação ~300 ms).
      final previousOwnerId = _activeOwnerId;
      final previousOwnerType = _audioOwnerType;

      invalidateRecovery();
      _publishSpeechStopped(ownerId: previousOwnerId, reason: 'route_pop');
      _activeOwnerId = null;
      _listeningStartInProgress = false;
      VoiceRuntimeRegistry.instance.setActiveOwner(null);
      _audioOwnerType = VoiceAudioOwnerType.none;

      diagnostics.record(
        VoiceDiagnosticEventType.listeningStopped,
        ownerId: previousOwnerId,
        reason: 'route_pop',
        message: 'Owner STT liberado sincronamente no pop da rota.',
      );
      _publishAudioOwnershipChanged(
        previousOwnerType,
        _audioOwnerType,
        ownerId: previousOwnerId,
        reason: 'route_pop',
      );
      if (stateMachine.state == VoiceState.listening) {
        stateMachine.transitionTo(
          VoiceState.idle,
          ownerId: previousOwnerId,
          reason: 'route_pop',
        );
      }

      // Cancela o hardware em background; SpeechService.startListening()
      // lida com isListening=true naturalmente (stop + delay 300ms interno).
      unawaited(speech.cancelListening());
      notifyListeners();
    } else {
      invalidateRecovery();
    }
  }

  void enterRecordingMode({String ownerId = 'editor', String? reason}) {
    invalidateRecovery();
    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(ownerId);
    _audioOwnerType = VoiceAudioOwnerType.recorder;
    _generation++;
    unawaited(speech.cancelListening());
    stateMachine.transitionTo(
      VoiceState.recording,
      ownerId: ownerId,
      message: 'Microfone reservado para gravacao.',
      reason: reason ?? 'recording_started',
      force: true,
    );
    diagnostics.record(
      VoiceDiagnosticEventType.recordingStarted,
      ownerId: ownerId,
      reason: reason,
      message: 'Modo gravacao entrou como dono do microfone.',
    );
    _publishAudioOwnershipChanged(
      previousOwnerType,
      VoiceAudioOwnerType.recorder,
      ownerId: ownerId,
      reason: reason ?? 'recording_started',
    );
    diagnostics.eventBus.publish(
      RecordingStartedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason ?? 'recording_started',
      ),
    );
    notifyListeners();
  }

  void exitRecordingMode({String ownerId = 'editor', String? reason}) {
    final previousOwnerType = _audioOwnerType;
    if (_audioOwnerType == VoiceAudioOwnerType.recorder) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    if (_activeOwnerId == ownerId) {
      _activeOwnerId = null;
    }
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    stateMachine.transitionTo(
      VoiceState.idle,
      ownerId: ownerId,
      reason: reason ?? 'recording_stopped',
      force: true,
    );
    diagnostics.record(
      VoiceDiagnosticEventType.recordingStopped,
      ownerId: ownerId,
      reason: reason,
      message: 'Modo gravacao liberou o microfone.',
    );
    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: ownerId,
      reason: reason ?? 'recording_stopped',
    );
    diagnostics.eventBus.publish(
      RecordingStoppedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason ?? 'recording_stopped',
      ),
    );
    notifyListeners();
  }

  Future<bool> beginPlayback({required String ownerId, String? reason}) async {
    if (_audioOwnerType == VoiceAudioOwnerType.recorder) {
      diagnostics.record(
        VoiceDiagnosticEventType.microphoneConflict,
        ownerId: ownerId,
        reason: 'recording_active',
        message: 'Playback solicitado durante gravacao ativa.',
      );
      diagnostics.eventBus.publish(
        MicrophoneConflictDetectedEvent(
          source: 'voice_session_manager',
          ownerId: ownerId,
          reason: 'recording_active',
          conflict: 'recorder_blocks_playback',
          message: 'Playback solicitado durante gravacao ativa.',
        ),
      );
      return false;
    }

    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      await cancelListening(
        ownerId: _activeOwnerId,
        reason: 'playback_preempts_stt',
      );
    }

    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = ownerId;
    VoiceRuntimeRegistry.instance.setActiveOwner(ownerId);
    _audioOwnerType = VoiceAudioOwnerType.playback;
    stateMachine.transitionTo(
      VoiceState.executing,
      ownerId: ownerId,
      reason: reason ?? 'playback_started',
    );
    diagnostics.record(
      VoiceDiagnosticEventType.playbackStarted,
      ownerId: ownerId,
      reason: reason,
      message: 'Playback assumiu execucao de audio.',
    );
    _publishAudioOwnershipChanged(
      previousOwnerType,
      VoiceAudioOwnerType.playback,
      ownerId: ownerId,
      reason: reason ?? 'playback_started',
    );
    diagnostics.eventBus.publish(
      PlaybackStartedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason ?? 'playback_started',
      ),
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> beginAudioOutput({required String ownerId, String? reason}) {
    return beginPlayback(ownerId: ownerId, reason: reason ?? 'audio_output');
  }

  void endPlayback({required String ownerId, String? reason}) {
    final previousOwnerType = _audioOwnerType;
    if (_audioOwnerType == VoiceAudioOwnerType.playback) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    if (_activeOwnerId == ownerId) {
      _activeOwnerId = null;
    }
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    stateMachine.transitionTo(
      VoiceState.idle,
      ownerId: ownerId,
      reason: reason ?? 'playback_stopped',
    );
    diagnostics.record(
      VoiceDiagnosticEventType.playbackStopped,
      ownerId: ownerId,
      reason: reason,
      message: 'Playback liberou a sessao de audio.',
    );
    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: ownerId,
      reason: reason ?? 'playback_stopped',
    );
    diagnostics.eventBus.publish(
      PlaybackStoppedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason ?? 'playback_stopped',
      ),
    );
    notifyListeners();
  }

  @override
  void endAudioOutput({required String ownerId, String? reason}) {
    endPlayback(ownerId: ownerId, reason: reason ?? 'audio_output_stopped');
  }

  void markProcessing({required String ownerId, String? message}) {
    stateMachine.transitionTo(
      VoiceState.processing,
      ownerId: ownerId,
      message: message,
      reason: 'processing_command',
    );
  }

  void markExecuting({required String ownerId, String? message}) {
    stateMachine.transitionTo(
      VoiceState.executing,
      ownerId: ownerId,
      message: message,
      reason: 'executing_command',
    );
  }

  void markDisabled({String? ownerId, String? reason}) {
    invalidateRecovery();
    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    stateMachine.transitionTo(
      VoiceState.disabled,
      ownerId: ownerId,
      reason: reason ?? 'voice_disabled',
      force: true,
    );
    notifyListeners();
  }

  void registerFailure({
    String? ownerId,
    required String reason,
    required String message,
  }) {
    _lastFailureReason = reason;
    stateMachine.transitionTo(
      VoiceState.error,
      ownerId: ownerId ?? _activeOwnerId,
      message: message,
      reason: reason,
      force: true,
    );
    diagnostics.record(
      VoiceDiagnosticEventType.error,
      ownerId: ownerId ?? _activeOwnerId,
      reason: reason,
      message: message,
    );
    diagnostics.eventBus.publish(
      SpeechListeningFailedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId ?? _activeOwnerId,
        reason: reason,
        message: message,
        correlationId: _activeListeningCorrelationId,
      ),
    );
    notifyListeners();
  }

  void scheduleRecovery({
    required String ownerId,
    required bool Function() shouldRecover,
    required Future<void> Function() onRecover,
    VoiceRecoveryReason reason = VoiceRecoveryReason.normal,
  }) {
    final attempts = stateMachine.snapshot.recoveryAttempts;
    final correlationId = 'recovery_${ownerId}_$_generation';
    if (attempts >= maxRecoveryAttempts) {
      diagnostics.record(
        VoiceDiagnosticEventType.recoverySkipped,
        ownerId: ownerId,
        reason: 'max_attempts',
        message: 'Recovery ignorado apos $attempts tentativas.',
      );
      diagnostics.eventBus.publish(
        RecoverySkippedEvent(
          source: 'voice_session_manager',
          ownerId: ownerId,
          reason: 'max_attempts',
          correlationId: correlationId,
          message: 'Recovery ignorado apos $attempts tentativas.',
          metadata: {'attempts': attempts},
        ),
      );
      stateMachine.transitionTo(
        VoiceState.error,
        ownerId: ownerId,
        reason: 'max_recovery_attempts',
        force: true,
      );
      return;
    }

    if (_activeRecoveryCorrelationId != null) {
      diagnostics.record(
        VoiceDiagnosticEventType.recoverySkipped,
        ownerId: ownerId,
        reason: 'recovery_already_pending',
        message: 'Recovery ignorado: ja existe tentativa pendente.',
      );
      return;
    }

    final generation = _generation;
    final delay = restartDelayFor(reason);
    _activeRecoveryCorrelationId = correlationId;
    final sessionToken = VoiceRuntimeRegistry.instance.registerVoiceSession(
      ownerId: ownerId,
      shouldRecover: () {
        final conditionMet = generation == _generation && shouldRecover();
        // Liberar latch quando a condição falha naturalmente (sem invalidação).
        // Sem isso, _activeRecoveryCorrelationId fica preso após condition_false
        // e bloqueia recoveries futuros com 'recovery_already_pending'.
        if (!conditionMet && _activeRecoveryCorrelationId == correlationId) {
          _activeRecoveryCorrelationId = null;
        }
        return conditionMet;
      },
      recover: () async {
        if (generation != _generation) {
          return;
        }
        stateMachine.incrementRecoveryAttempts();
        // Limpar latch antes de executar o recovery para liberar slot imediatamente.
        if (_activeRecoveryCorrelationId == correlationId) {
          _activeRecoveryCorrelationId = null;
        }
        await onRecover();
      },
      metadata: {'generation': generation, 'reason': reason.name},
    );
    stateMachine.transitionTo(
      VoiceState.recovering,
      ownerId: ownerId,
      reason: reason.name,
      recoveryAttempts: attempts,
      force: true,
    );
    diagnostics.record(
      VoiceDiagnosticEventType.recoveryScheduled,
      ownerId: ownerId,
      reason: reason.name,
      message: 'Recovery agendado em ${delay.inMilliseconds}ms.',
    );
    diagnostics.eventBus.publish(
      RecoverVoiceSessionRequestedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason.name,
        correlationId: correlationId,
        metadata: {
          'delayMs': delay.inMilliseconds,
          'attempts': attempts,
          'sessionToken': sessionToken,
        },
      ),
    );
  }

  void invalidateRecovery() {
    _generation++;
    final correlationId = _activeRecoveryCorrelationId;
    if (correlationId != null) {
      diagnostics.eventBus.cancelChain(
        correlationId,
        source: 'voice_session_manager',
        reason: 'recovery_invalidated',
      );
      _activeRecoveryCorrelationId = null;
    }
  }

  void resetForTesting() {
    _activeOwnerId = null;
    _audioOwnerType = VoiceAudioOwnerType.none;
    _lastFailureReason = null;
    _busyCooldownUntil = null;
    _listeningStartInProgress = false;
    invalidateRecovery();
    VoiceRuntimeEngine.instance.resetForTesting();
    VoiceRuntimeRegistry.instance.resetForTesting();
    stateMachine.reset();
    diagnostics.eventBus.clearForTesting();
    notifyListeners();
  }

  Future<void> _handleStopVoiceCaptureRequested(
    StopVoiceCaptureRequestedEvent event,
  ) async {
    if (!VoiceRuntimeRegistry.instance.canMutate(
      source: event.source,
      ownerId: event.ownerId,
    )) {
      diagnostics.eventBus.publish(
        StopVoiceCaptureRejectedEvent(
          source: 'voice_session_manager',
          ownerId: event.ownerId,
          reason: 'ownership_required',
          correlationId: event.correlationId,
          causationId: event.id,
          metadata: {
            'eventSource': event.source,
            'activeOwnerId': VoiceRuntimeRegistry.instance.ownership.ownerId,
          },
        ),
      );
      return;
    }

    if (_activeOwnerId != null &&
        event.ownerId != null &&
        event.ownerId != _activeOwnerId) {
      diagnostics.eventBus.publish(
        RecoverySkippedEvent(
          source: 'voice_session_manager',
          ownerId: event.ownerId,
          reason: 'stop_capture_owner_mismatch',
          correlationId: event.correlationId,
          causationId: event.id,
          message: 'Stop de captura ignorado: outro owner esta ativo.',
          metadata: {'activeOwnerId': _activeOwnerId},
        ),
      );
      return;
    }

    await cancelListening(
      ownerId: event.ownerId == _activeOwnerId ? event.ownerId : null,
      reason: event.reason ?? 'runtime_stop_capture_requested',
    );
  }

  void _publishSpeechStopped({String? ownerId, required String reason}) {
    if (!_speechHardwareStarted || _activeListeningCorrelationId == null) {
      return;
    }
    diagnostics.eventBus.publish(
      SpeechListeningStoppedEvent(
        source: 'voice_session_manager',
        ownerId: ownerId,
        reason: reason,
        correlationId: _activeListeningCorrelationId,
      ),
    );
    _speechHardwareStarted = false;
    _activeListeningCorrelationId = null;
  }

  void _releaseStoppedSpeech({String? ownerId, required String reason}) {
    _publishSpeechStopped(ownerId: ownerId, reason: reason);
    if (ownerId != null && _activeOwnerId != ownerId) {
      return;
    }

    final previousOwnerType = _audioOwnerType;
    _activeOwnerId = null;
    VoiceRuntimeRegistry.instance.setActiveOwner(null);
    if (_audioOwnerType == VoiceAudioOwnerType.stt) {
      _audioOwnerType = VoiceAudioOwnerType.none;
    }
    _publishAudioOwnershipChanged(
      previousOwnerType,
      _audioOwnerType,
      ownerId: ownerId,
      reason: reason,
    );
    notifyListeners();
  }

  void _recordStartSkipped({
    required String ownerId,
    required String reason,
    required String message,
  }) {
    diagnostics.record(
      VoiceDiagnosticEventType.recoverySkipped,
      ownerId: ownerId,
      reason: reason,
      message: message,
    );
  }

  void _publishAudioOwnershipChanged(
    VoiceAudioOwnerType from,
    VoiceAudioOwnerType to, {
    String? ownerId,
    String? reason,
  }) {
    if (from == to) {
      return;
    }

    diagnostics.eventBus.publish(
      AudioOwnershipChangedEvent(
        source: 'voice_session_manager',
        from: from.name,
        to: to.name,
        ownerId: ownerId,
        reason: reason,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_controlSubscription.cancel());
    super.dispose();
  }
}
