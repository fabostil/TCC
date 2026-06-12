import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:flutter/services.dart';

import '../../../models/google_identity.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message, {this.isConfigurationError = false});

  final String message;
  final bool isConfigurationError;

  @override
  String toString() => message;
}

const String googleLoginGenericMessage =
    'Não foi possível concluir o login com Google neste dispositivo.';

const String googleLoginConfigurationMessage =
    'Não foi possível concluir o login com Google neste dispositivo. '
    'Verifique a configuração do app.';

abstract class GoogleSignInClient {
  Future<void> initialize({String? serverClientId});

  bool supportsAuthenticate();

  Future<GoogleSignInUser?> authenticate();

  Future<void> signOut();
}

abstract class GoogleSignInUser {
  String get id;

  String get email;

  String? get displayName;

  String? get photoUrl;

  GoogleSignInTokens get authentication;
}

class GoogleSignInTokens {
  const GoogleSignInTokens({required this.idToken});

  final String? idToken;
}

class GoogleSignInPluginClient implements GoogleSignInClient {
  GoogleSignInPluginClient({google_sign_in.GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? google_sign_in.GoogleSignIn.instance;

  final google_sign_in.GoogleSignIn _googleSignIn;

  @override
  Future<void> initialize({String? serverClientId}) {
    return _googleSignIn.initialize(serverClientId: serverClientId);
  }

  @override
  bool supportsAuthenticate() => _googleSignIn.supportsAuthenticate();

  @override
  Future<GoogleSignInUser> authenticate() async {
    final account = await _googleSignIn.authenticate();
    return GoogleSignInPluginUser(account);
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}

class GoogleSignInPluginUser implements GoogleSignInUser {
  const GoogleSignInPluginUser(this._account);

  final google_sign_in.GoogleSignInAccount _account;

  @override
  String get id => _account.id;

  @override
  String get email => _account.email;

  @override
  String? get displayName => _account.displayName;

  @override
  String? get photoUrl => _account.photoUrl;

  @override
  GoogleSignInTokens get authentication {
    return GoogleSignInTokens(idToken: _account.authentication.idToken);
  }
}

class GoogleAuthService {
  GoogleAuthService._internal({GoogleSignInClient? client})
    : _client = client ?? GoogleSignInPluginClient();

  GoogleAuthService.test({required GoogleSignInClient client})
    : _client = client;

  static final GoogleAuthService instance = GoogleAuthService._internal();

  final GoogleSignInClient _client;
  Future<void>? _initializeFuture;

  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  Future<void> _initialize() {
    return _initializeFuture ??= _client
        .initialize(
          serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
        )
        .catchError((Object error) {
          _initializeFuture = null;
          throw error;
        });
  }

  /// Autentica somente no provedor Google e retorna a identidade externa.
  ///
  /// O idToken e exigido e preservado em [GoogleIdentity] para validacao futura
  /// por backend/Firebase Auth, mas nao e validado server-side nesta etapa.
  Future<GoogleIdentity?> entrarComGoogle() async {
    try {
      await _initialize();

      if (!_client.supportsAuthenticate()) {
        throw const GoogleAuthException(
          'Login Google interativo nao esta disponivel nesta plataforma.',
        );
      }

      final account = await _client.authenticate();
      if (account == null) {
        return null;
      }

      final idToken = account.authentication.idToken;

      if (_isBlank(idToken) ||
          _isBlank(account.id) ||
          _isBlank(account.email)) {
        throw const GoogleAuthException(googleLoginGenericMessage);
      }

      return GoogleIdentity(
        nome: account.displayName ?? account.email.split('@').first,
        email: account.email,
        googleId: account.id,
        fotoUrl: account.photoUrl,
        idToken: idToken!.trim(),
      );
    } on GoogleAuthException {
      rethrow;
    } on google_sign_in.GoogleSignInException catch (e) {
      if (e.code == google_sign_in.GoogleSignInExceptionCode.canceled) {
        return null;
      }

      if (e.code ==
              google_sign_in
                  .GoogleSignInExceptionCode
                  .clientConfigurationError ||
          e.code ==
              google_sign_in
                  .GoogleSignInExceptionCode
                  .providerConfigurationError) {
        throw const GoogleAuthException(
          googleLoginConfigurationMessage,
          isConfigurationError: true,
        );
      }

      throw const GoogleAuthException(googleLoginGenericMessage);
    } on PlatformException catch (e) {
      if (_isConfigurationPlatformError(e)) {
        throw const GoogleAuthException(
          googleLoginConfigurationMessage,
          isConfigurationError: true,
        );
      }

      throw const GoogleAuthException(googleLoginGenericMessage);
    } catch (_) {
      throw const GoogleAuthException(googleLoginGenericMessage);
    }
  }

  Future<void> sair() async {
    await _initialize();
    await _client.signOut();
  }
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

bool _isConfigurationPlatformError(PlatformException error) {
  final code = error.code.toLowerCase();
  final message = error.message?.toLowerCase() ?? '';
  return code.contains('developer_error') ||
      code.contains('sign_in_failed') ||
      code.contains('api_exception') ||
      message.contains('developer_error') ||
      message.contains('sign_in_failed') ||
      message.contains('api_exception');
}
