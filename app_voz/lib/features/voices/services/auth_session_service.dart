import '../coordination/voice_session_manager.dart';
import '../realtime/runtime/runtime_registry.dart';
import '../realtime/runtime/voice_realtime_ecosystem.dart';
import 'google_auth_service.dart';

/// Centraliza o encerramento da sessao autenticada e dos contextos de voz.
class AuthSessionService {
  AuthSessionService({
    Future<void> Function()? googleSignOut,
    Future<void> Function()? stopActiveVoiceSession,
    void Function()? clearActiveVoiceContext,
    void Function()? clearRuntimeVoiceSession,
  }) : _googleSignOut = googleSignOut,
       _stopActiveVoiceSession = stopActiveVoiceSession,
       _clearActiveVoiceContext = clearActiveVoiceContext,
       _clearRuntimeVoiceSession = clearRuntimeVoiceSession;

  static final AuthSessionService instance = AuthSessionService();

  static const _stopActiveVoiceSessionStep = 'stopActiveVoiceSession';
  static const _clearActiveVoiceContextStep = 'clearActiveVoiceContext';
  static const _clearRuntimeVoiceSessionStep = 'clearRuntimeVoiceSession';
  static const _googleSignOutStep = 'googleSignOut';
  static const _authLogoutReason = 'auth_logout';

  final Future<void> Function()? _googleSignOut;
  final Future<void> Function()? _stopActiveVoiceSession;
  final void Function()? _clearActiveVoiceContext;
  final void Function()? _clearRuntimeVoiceSession;

  /// Encerra a sessao ativa de voz, limpa contexto/runtime e sai do Google.
  ///
  /// Todas as etapas sao tentadas. Se alguma falhar, a primeira falha e
  /// relancada ao final como [AuthSessionLogoutException].
  Future<void> logout() async {
    AuthSessionLogoutException? firstFailure;

    Future<void> recordFailure(
      String step,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstFailure ??= AuthSessionLogoutException(
          failedStep: step,
          originalError: error,
          originalStackTrace: stackTrace,
        );
      }
    }

    await recordFailure(
      _stopActiveVoiceSessionStep,
      _stopActiveVoiceSession ?? _stopDefaultActiveVoiceSession,
    );
    await recordFailure(_clearActiveVoiceContextStep, () async {
      (_clearActiveVoiceContext ??
              VoiceRealtimeEcosystem.instance.clearActiveContext)
          .call();
    });
    await recordFailure(_clearRuntimeVoiceSessionStep, () async {
      final clearRuntimeVoiceSession = _clearRuntimeVoiceSession;
      if (clearRuntimeVoiceSession != null) {
        clearRuntimeVoiceSession();
        return;
      }
      VoiceRuntimeRegistry.instance.clearVoiceSession();
    });
    await recordFailure(
      _googleSignOutStep,
      _googleSignOut ?? GoogleAuthService.instance.sair,
    );

    final failure = firstFailure;
    if (failure != null) {
      throw failure;
    }
  }

  Future<void> _stopDefaultActiveVoiceSession() {
    final manager = VoiceSessionManager.instance;
    return manager.cancelListening(
      ownerId: manager.activeOwnerId,
      reason: _authLogoutReason,
    );
  }
}

/// Excecao tecnica de logout que preserva a primeira etapa com falha.
class AuthSessionLogoutException implements Exception {
  const AuthSessionLogoutException({
    required this.failedStep,
    required this.originalError,
    required this.originalStackTrace,
  });

  final String failedStep;
  final Object originalError;
  final StackTrace originalStackTrace;

  @override
  String toString() {
    return 'AuthSessionLogoutException('
        'step: $failedStep, error: $originalError)';
  }
}
