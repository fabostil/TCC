import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../models/usuario.dart';
import '../../../repositories/usuario_repository.dart';
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
    Future<String> Function()? sessionDirectoryPathProvider,
    Future<Usuario?> Function(int id)? userById,
  }) : _googleSignOut = googleSignOut,
       _stopActiveVoiceSession = stopActiveVoiceSession,
       _clearActiveVoiceContext = clearActiveVoiceContext,
       _clearRuntimeVoiceSession = clearRuntimeVoiceSession,
       _sessionDirectoryPathProvider = sessionDirectoryPathProvider,
       _userById = userById;

  static final AuthSessionService instance = AuthSessionService();

  static const _stopActiveVoiceSessionStep = 'stopActiveVoiceSession';
  static const _clearActiveVoiceContextStep = 'clearActiveVoiceContext';
  static const _clearRuntimeVoiceSessionStep = 'clearRuntimeVoiceSession';
  static const _clearPersistedSessionStep = 'clearPersistedSession';
  static const _googleSignOutStep = 'googleSignOut';
  static const _authLogoutReason = 'auth_logout';
  static const _sessionFileName = 'auth_session_user_id.txt';

  final Future<void> Function()? _googleSignOut;
  final Future<void> Function()? _stopActiveVoiceSession;
  final void Function()? _clearActiveVoiceContext;
  final void Function()? _clearRuntimeVoiceSession;
  final Future<String> Function()? _sessionDirectoryPathProvider;
  final Future<Usuario?> Function(int id)? _userById;

  /// Persiste somente o id local do usuario autenticado.
  ///
  /// Nao grava senha, hash, token Google, API key ou qualquer segredo.
  Future<void> saveAuthenticatedUser(Usuario usuario) async {
    final id = usuario.id;
    if (id == null) {
      await clearPersistedSession();
      return;
    }

    final file = await _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(id.toString(), flush: true);
  }

  Future<Usuario?> restoreAuthenticatedUser() async {
    final file = await _sessionFile();
    if (!await file.exists()) {
      return null;
    }

    final raw = (await file.readAsString()).trim();
    final id = int.tryParse(raw);
    if (id == null || id <= 0) {
      await clearPersistedSession();
      return null;
    }

    final loader = _userById ?? UsuarioRepository.instance.buscarPorId;
    final usuario = await loader(id);
    if (usuario == null) {
      await clearPersistedSession();
      return null;
    }

    return usuario;
  }

  Future<void> clearPersistedSession() async {
    final file = await _sessionFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

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
    await recordFailure(_clearPersistedSessionStep, clearPersistedSession);
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

  Future<File> _sessionFile() async {
    final directoryPath = await _sessionDirectoryPath();
    return File(path.join(directoryPath, _sessionFileName));
  }

  Future<String> _sessionDirectoryPath() async {
    final provider = _sessionDirectoryPathProvider;
    if (provider != null) {
      return provider();
    }

    final directory = await getApplicationSupportDirectory();
    return directory.path;
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
