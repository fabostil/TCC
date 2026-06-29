import 'package:flutter/foundation.dart';

import 'voice_session_manager.dart';

enum VoiceRestartReason { normal, afterError }

/// Fachada de compatibilidade para o codigo existente.
///
/// A decisao central de ownership, conflito de microfone, recovery e logging
/// agora vive em [VoiceSessionManager]. Esta classe permanece para manter as
/// paginas atuais funcionando enquanto a refatoracao de voz avanca por etapas.
class VoiceListeningCoordinator {
  VoiceListeningCoordinator._();

  static final VoiceListeningCoordinator instance =
      VoiceListeningCoordinator._();

  static const Duration restartDelayDefault =
      VoiceSessionManager.restartDelayDefault;
  static const Duration restartDelayAfterError =
      VoiceSessionManager.restartDelayAfterError;

  final VoiceSessionManager sessionManager = VoiceSessionManager.instance;

  String? get activeOwnerId => sessionManager.activeOwnerId;

  bool get recordingModeActive => sessionManager.recordingActive;

  @visibleForTesting
  void resetForTesting() {
    sessionManager.resetForTesting();
  }

  Duration restartDelayFor(VoiceRestartReason reason) {
    return sessionManager.restartDelayFor(reason._toRecoveryReason());
  }

  bool canStartListening(String ownerId) {
    return sessionManager.canClaimListening(ownerId);
  }

  bool claimListening(String ownerId) {
    return sessionManager.claimListening(ownerId);
  }

  void releaseOwner(String ownerId) {
    sessionManager.releaseOwner(ownerId);
  }

  Future<void> releaseAndStop(String ownerId) {
    return sessionManager.stopListening(ownerId);
  }

  Future<void> cancelActiveListening() {
    return sessionManager.cancelListening();
  }

  Future<void> prepareForNavigation() {
    return sessionManager.prepareForNavigation();
  }

  void onRouteDidPush() {
    sessionManager.onRouteDidPush();
  }

  void onRouteDidPop() {
    sessionManager.onRouteDidPop();
  }

  void enterRecordingMode() {
    sessionManager.enterRecordingMode();
  }

  void exitRecordingMode() {
    sessionManager.exitRecordingMode();
  }

  void scheduleContinuousRestart({
    required String ownerId,
    required bool Function() shouldRestart,
    required Future<void> Function() onRestart,
    VoiceRestartReason reason = VoiceRestartReason.normal,
  }) {
    sessionManager.scheduleRecovery(
      ownerId: ownerId,
      reason: reason._toRecoveryReason(),
      shouldRecover: shouldRestart,
      onRecover: onRestart,
    );
  }
}

extension on VoiceRestartReason {
  VoiceRecoveryReason _toRecoveryReason() {
    return switch (this) {
      VoiceRestartReason.normal => VoiceRecoveryReason.normal,
      VoiceRestartReason.afterError => VoiceRecoveryReason.afterError,
    };
  }
}
