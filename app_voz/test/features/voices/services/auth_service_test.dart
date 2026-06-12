import 'package:app_voz/features/voices/services/auth_service.dart';
import 'package:app_voz/features/voices/services/google_auth_service.dart';
import 'package:app_voz/models/google_identity.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService', () {
    test('entrarComGoogle retorna null quando provedor retorna null', () async {
      final service = AuthService(googleIdentityProvider: () async => null);

      final usuario = await service.entrarComGoogle();

      expect(usuario, isNull);
    });

    test('entrarComGoogle chama resolver com dados da identidade', () async {
      final chamadas = <Map<String, Object?>>[];
      final esperado = _usuario();
      final service = AuthService(
        googleIdentityProvider: () async => const GoogleIdentity(
          nome: 'Alex Google',
          email: 'alex@example.com',
          googleId: 'google-123',
          fotoUrl: 'https://example.com/foto.png',
          idToken: 'id-token',
        ),
        googleUserResolver:
            ({
              required nome,
              required email,
              required googleId,
              fotoUrl,
            }) async {
              chamadas.add({
                'nome': nome,
                'email': email,
                'googleId': googleId,
                'fotoUrl': fotoUrl,
              });
              return esperado;
            },
      );

      final usuario = await service.entrarComGoogle();

      expect(usuario, esperado);
      expect(chamadas, [
        {
          'nome': 'Alex Google',
          'email': 'alex@example.com',
          'googleId': 'google-123',
          'fotoUrl': 'https://example.com/foto.png',
        },
      ]);
    });

    test('autenticarUsuario delega para localAuthenticator', () async {
      final esperado = _usuario(email: 'local@example.com');
      final chamadas = <Map<String, String>>[];
      final service = AuthService(
        localAuthenticator: ({required email, required senha}) async {
          chamadas.add({'email': email, 'senha': senha});
          return esperado;
        },
      );

      final usuario = await service.autenticarUsuario(
        email: 'local@example.com',
        senha: 'senha123',
      );

      expect(usuario, esperado);
      expect(chamadas, [
        {'email': 'local@example.com', 'senha': 'senha123'},
      ]);
    });

    test('cadastrarUsuario delega para localRegister', () async {
      final chamadas = <Map<String, String>>[];
      final service = AuthService(
        localRegister: ({required nome, required email, required senha}) async {
          chamadas.add({'nome': nome, 'email': email, 'senha': senha});
          return true;
        },
      );

      final sucesso = await service.cadastrarUsuario(
        nome: 'Alex',
        email: 'alex@example.com',
        senha: 'senha123',
      );

      expect(sucesso, isTrue);
      expect(chamadas, [
        {'nome': 'Alex', 'email': 'alex@example.com', 'senha': 'senha123'},
      ]);
    });

    test('erro do googleIdentityProvider e propagado', () async {
      const erro = GoogleAuthException(googleLoginConfigurationMessage);
      final service = AuthService(
        googleIdentityProvider: () async => throw erro,
      );

      expect(service.entrarComGoogle(), throwsA(same(erro)));
    });

    test('erro do googleUserResolver vira falha controlada de conta', () async {
      final erro = StateError('resolver failed');
      final service = AuthService(
        googleIdentityProvider: () async => const GoogleIdentity(
          nome: 'Alex',
          email: 'alex@example.com',
          googleId: 'google-123',
          idToken: 'id-token',
        ),
        googleUserResolver:
            ({
              required nome,
              required email,
              required googleId,
              fotoUrl,
            }) async {
              throw erro;
            },
      );

      expect(
        service.entrarComGoogle(),
        throwsA(
          isA<AuthGoogleLoginException>().having(
            (error) => error.message,
            'message',
            authGoogleAccountPreparationMessage,
          ),
        ),
      );
    });
  });
}

Usuario _usuario({String email = 'alex@example.com'}) {
  return Usuario(
    id: 1,
    nome: 'Alex',
    email: email,
    senhaHash: 'external_provider',
    authProvider: 'google',
    googleId: 'google-123',
  );
}
