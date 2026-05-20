import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_utils.dart';

void main() {
  const databaseName = 'usuario_repository_test.db';
  late UsuarioRepository repository;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    repository = UsuarioRepository.instance;
    await useRepositoryTestDatabase(databaseName);
    await resetRepositoryTestDatabase(databaseName);
  });

  tearDown(() async {
    await resetRepositoryTestDatabase(databaseName);
  });

  group('UsuarioRepository', () {
    test('cadastra e autentica usuario local normalizando e-mail', () async {
      final cadastrado = await repository.cadastrarUsuario(
        nome: 'Alex',
        email: ' ALEX@EXAMPLE.COM ',
        senha: 'abc12345',
      );

      final usuario = await repository.autenticarUsuario(
        email: 'alex@example.com',
        senha: 'abc12345',
      );

      expect(cadastrado, isTrue);
      expect(usuario, isNotNull);
      expect(usuario!.email, 'alex@example.com');
      expect(usuario.authProvider, 'local');
      expect(usuario.dataCadastro, isNotNull);
    });

    test('rejeita cadastro local duplicado por e-mail normalizado', () async {
      await repository.cadastrarUsuario(
        nome: 'Alex',
        email: 'alex@example.com',
        senha: 'abc12345',
      );

      final duplicado = await repository.cadastrarUsuario(
        nome: 'Outro',
        email: ' ALEX@EXAMPLE.COM ',
        senha: 'abc12345',
      );

      expect(duplicado, isFalse);
    });

    test('cria usuario local a partir de conta Google verificada', () async {
      final usuario = await repository.autenticarComGoogle(
        nome: 'Alex Google',
        email: 'alex.google@example.com',
        googleId: 'google-123',
        fotoUrl: 'https://example.com/foto.png',
      );

      expect(usuario.id, isNotNull);
      expect(usuario.nome, 'Alex Google');
      expect(usuario.email, 'alex.google@example.com');
      expect(usuario.authProvider, 'google');
      expect(usuario.googleId, 'google-123');
      expect(usuario.fotoUrl, 'https://example.com/foto.png');
    });

    test(
      'vincula Google a usuario local existente sem remover senha',
      () async {
        await repository.cadastrarUsuario(
          nome: 'Alex Local',
          email: 'alex@example.com',
          senha: 'abc12345',
        );

        final vinculado = await repository.autenticarComGoogle(
          nome: 'Alex Google',
          email: 'ALEX@EXAMPLE.COM',
          googleId: 'google-456',
        );

        final loginLocal = await repository.autenticarUsuario(
          email: 'alex@example.com',
          senha: 'abc12345',
        );

        expect(vinculado.authProvider, 'local_google');
        expect(vinculado.googleId, 'google-456');
        expect(vinculado.nome, 'Alex Local');
        expect(loginLocal, isNotNull);
        expect(loginLocal!.googleId, 'google-456');
      },
    );
  });
}
