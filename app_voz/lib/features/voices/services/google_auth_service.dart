import 'package:google_sign_in/google_sign_in.dart';

import '../../../models/usuario.dart';
import '../../../repositories/usuario_repository.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleAuthService {
  GoogleAuthService._internal();

  static final GoogleAuthService instance = GoogleAuthService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _initializeFuture;

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  Future<void> _initialize() {
    return _initializeFuture ??= _googleSignIn
        .initialize(
          serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
        )
        .catchError((Object error) {
          _initializeFuture = null;
          throw error;
        });
  }

  Future<Usuario?> entrarComGoogle() async {
    try {
      await _initialize();

      if (!_googleSignIn.supportsAuthenticate()) {
        throw const GoogleAuthException(
          'Login Google interativo nao esta disponivel nesta plataforma.',
        );
      }

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException(
          'A conta Google nao retornou token de verificacao.',
        );
      }

      return UsuarioRepository.instance.autenticarComGoogle(
        nome: account.displayName ?? account.email.split('@').first,
        email: account.email,
        googleId: account.id,
        fotoUrl: account.photoUrl,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }

      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const GoogleAuthException(
          'Configure o OAuth Android do Google para este aplicativo.',
        );
      }

      throw GoogleAuthException(
        e.description ?? 'Nao foi possivel entrar com Google.',
      );
    }
  }

  Future<void> sair() async {
    await _initialize();
    await _googleSignIn.signOut();
  }
}
