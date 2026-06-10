import 'package:app_voz/features/voices/services/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoogleAuthService', () {
    test('entrarComGoogle retorna null quando usuario cancela login', () async {
      final client = _FakeGoogleSignInClient(authenticateResult: null);
      final service = GoogleAuthService.test(client: client);

      final identity = await service.entrarComGoogle();

      expect(identity, isNull);
      expect(client.initializeCalls, 1);
      expect(client.authenticateCalls, 1);
      expect(client.authenticationReads, 0);
    });

    test('entrarComGoogle retorna GoogleIdentity com idToken valido', () async {
      var authenticationReads = 0;
      final client = _FakeGoogleSignInClient(
        authenticateResult: _FakeGoogleSignInUser(
          id: 'google-123',
          email: 'alex@example.com',
          displayName: 'Alex Google',
          photoUrl: 'https://example.com/foto.png',
          idToken: 'fake-id-token',
          onAuthenticationRead: () => authenticationReads++,
        ),
      );
      final service = GoogleAuthService.test(client: client);

      final identity = await service.entrarComGoogle();

      expect(identity, isNotNull);
      expect(identity!.googleId, 'google-123');
      expect(identity.email, 'alex@example.com');
      expect(identity.nome, 'Alex Google');
      expect(identity.fotoUrl, 'https://example.com/foto.png');
      expect(identity.idToken, 'fake-id-token');
      expect(client.initializeCalls, 1);
      expect(client.authenticateCalls, 1);
      expect(authenticationReads, 1);
    });

    test(
      'entrarComGoogle usa prefixo do email quando displayName nao existe',
      () async {
        final client = _FakeGoogleSignInClient(
          authenticateResult: _FakeGoogleSignInUser(
            id: 'google-123',
            email: 'alex@example.com',
            idToken: 'fake-id-token',
          ),
        );
        final service = GoogleAuthService.test(client: client);

        final identity = await service.entrarComGoogle();

        expect(identity!.nome, 'alex');
      },
    );

    test('entrarComGoogle lanca GoogleAuthException quando idToken e nulo', () {
      final client = _FakeGoogleSignInClient(
        authenticateResult: _FakeGoogleSignInUser(
          id: 'google-123',
          email: 'alex@example.com',
          idToken: null,
        ),
      );
      final service = GoogleAuthService.test(client: client);

      expect(
        service.entrarComGoogle(),
        throwsA(
          isA<GoogleAuthException>().having(
            (error) => error.message,
            'message',
            'A conta Google nao retornou token de verificacao.',
          ),
        ),
      );
    });

    test(
      'entrarComGoogle lanca GoogleAuthException quando idToken e vazio',
      () {
        final client = _FakeGoogleSignInClient(
          authenticateResult: _FakeGoogleSignInUser(
            id: 'google-123',
            email: 'alex@example.com',
            idToken: '',
          ),
        );
        final service = GoogleAuthService.test(client: client);

        expect(service.entrarComGoogle(), throwsA(isA<GoogleAuthException>()));
      },
    );

    test('entrarComGoogle propaga erro de autenticacao inicial', () {
      final error = StateError('authenticate failed');
      final client = _FakeGoogleSignInClient(authenticateError: error);
      final service = GoogleAuthService.test(client: client);

      expect(service.entrarComGoogle(), throwsA(same(error)));
    });

    test('entrarComGoogle propaga erro ao obter tokens', () {
      final error = StateError('authentication failed');
      final client = _FakeGoogleSignInClient(
        authenticateResult: _FakeGoogleSignInUser(
          id: 'google-123',
          email: 'alex@example.com',
          idToken: 'fake-id-token',
          authenticationError: error,
        ),
      );
      final service = GoogleAuthService.test(client: client);

      expect(service.entrarComGoogle(), throwsA(same(error)));
    });

    test(
      'entrarComGoogle lanca GoogleAuthException quando plataforma nao suporta authenticate',
      () {
        final client = _FakeGoogleSignInClient(
          supportsAuthenticateResult: false,
        );
        final service = GoogleAuthService.test(client: client);

        expect(
          service.entrarComGoogle(),
          throwsA(
            isA<GoogleAuthException>().having(
              (error) => error.message,
              'message',
              'Login Google interativo nao esta disponivel nesta plataforma.',
            ),
          ),
        );
        expect(client.authenticateCalls, 0);
      },
    );

    test('sair inicializa cliente e chama signOut', () async {
      final client = _FakeGoogleSignInClient();
      final service = GoogleAuthService.test(client: client);

      await service.sair();

      expect(client.initializeCalls, 1);
      expect(client.signOutCalls, 1);
    });

    test('sair propaga erro de signOut', () {
      final error = StateError('signOut failed');
      final client = _FakeGoogleSignInClient(signOutError: error);
      final service = GoogleAuthService.test(client: client);

      expect(service.sair(), throwsA(same(error)));
    });
  });
}

class _FakeGoogleSignInClient implements GoogleSignInClient {
  _FakeGoogleSignInClient({
    this.authenticateResult,
    this.authenticateError,
    this.signOutError,
    this.supportsAuthenticateResult = true,
  });

  final GoogleSignInUser? authenticateResult;
  final Object? authenticateError;
  final Object? signOutError;
  final bool supportsAuthenticateResult;

  int initializeCalls = 0;
  int authenticateCalls = 0;
  int signOutCalls = 0;
  int authenticationReads = 0;

  @override
  Future<void> initialize({String? serverClientId}) async {
    initializeCalls++;
  }

  @override
  bool supportsAuthenticate() => supportsAuthenticateResult;

  @override
  Future<GoogleSignInUser?> authenticate() async {
    authenticateCalls++;
    final error = authenticateError;
    if (error != null) {
      throw error;
    }
    return authenticateResult;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) {
      throw error;
    }
  }
}

class _FakeGoogleSignInUser implements GoogleSignInUser {
  _FakeGoogleSignInUser({
    required this.id,
    required this.email,
    required this.idToken,
    this.displayName,
    this.photoUrl,
    this.authenticationError,
    this.onAuthenticationRead,
  });

  @override
  final String id;

  @override
  final String email;

  @override
  final String? displayName;

  @override
  final String? photoUrl;

  final String? idToken;
  final Object? authenticationError;
  final void Function()? onAuthenticationRead;

  @override
  GoogleSignInTokens get authentication {
    onAuthenticationRead?.call();
    final error = authenticationError;
    if (error != null) {
      throw error;
    }
    return GoogleSignInTokens(idToken: idToken);
  }
}
