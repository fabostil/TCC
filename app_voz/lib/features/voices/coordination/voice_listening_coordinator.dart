import 'dart:async';

import '../services/speech_service.dart';

enum VoiceRestartReason { normal, afterError }

/// Coordena propriedade do microfone/STT entre telas (Fase 1).
class VoiceListeningCoordinator {
  VoiceListeningCoordinator._();

  static final VoiceListeningCoordinator instance =
      VoiceListeningCoordinator._();

  static const Duration restartDelayDefault = Duration(milliseconds: 700);
  static const Duration restartDelayAfterError = Duration(seconds: 2);

  final SpeechService speech = SpeechService.instance;

  String? _activeOwnerId;
  bool _recordingModeActive = false;
  int _restartGeneration = 0;

  String? get activeOwnerId => _activeOwnerId;

  bool get recordingModeActive => _recordingModeActive;

  Duration restartDelayFor(VoiceRestartReason reason) {
    return reason == VoiceRestartReason.afterError
        ? restartDelayAfterError
        : restartDelayDefault;
  }

  bool canStartListening(String ownerId) {
    if (_recordingModeActive) {
      return false;
    }
    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      return false;
    }
    return true;
  }

  /// Reserva a escuta para [ownerId]. Retorna false se outra tela já possui.
  bool claimListening(String ownerId) {
    if (_recordingModeActive) {
      return false;
    }
    if (_activeOwnerId != null && _activeOwnerId != ownerId) {
      return false;
    }
    _activeOwnerId = ownerId;
    return true;
  }

  void releaseOwner(String ownerId) {
    if (_activeOwnerId == ownerId) {
      _activeOwnerId = null;
    }
  }

  Future<void> releaseAndStop(String ownerId) async {
    releaseOwner(ownerId);
    if (speech.isListening) {
      await speech.stopListening();
    }
  }

  Future<void> cancelActiveListening() async {
    _restartGeneration++;
    await speech.cancelListening();
    _activeOwnerId = null;
  }

  /// Antes de navegar por voz: libera microfone para a próxima rota.
  Future<void> prepareForNavigation() async {
    await cancelActiveListening();
  }

  /// Chamado pelo [VoiceRouteObserver] ao empilhar rota.
  void onRouteDidPush() {
    _restartGeneration++;
    unawaited(speech.cancelListening());
    _activeOwnerId = null;
  }

  /// Chamado pelo [VoiceRouteObserver] ao desempilhar rota.
  void onRouteDidPop() {
    _restartGeneration++;
  }

  void enterRecordingMode() {
    _recordingModeActive = true;
    _restartGeneration++;
    unawaited(speech.cancelListening());
    _activeOwnerId = null;
  }

  void exitRecordingMode() {
    _recordingModeActive = false;
  }

  void scheduleContinuousRestart({
    required String ownerId,
    required bool Function() shouldRestart,
    required Future<void> Function() onRestart,
    VoiceRestartReason reason = VoiceRestartReason.normal,
  }) {
    final generation = _restartGeneration;
    final delay = restartDelayFor(reason);

    Future.delayed(delay, () async {
      if (generation != _restartGeneration) {
        return;
      }
      if (!shouldRestart()) {
        return;
      }
      if (!canStartListening(ownerId)) {
        return;
      }
      await onRestart();
    });
  }
}
