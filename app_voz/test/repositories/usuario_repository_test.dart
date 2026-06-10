import 'package:app_voz/database/app_database.dart';
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
      expect(usuario.senhaAlgoritmo, 'pbkdf2_sha256');
      expect(usuario.senhaSalt, isNotNull);
      expect(usuario.senhaIteracoes, 120000);
      expect(usuario.senhaVersao, 2);
      expect(usuario.authProvider, 'local');
      expect(usuario.dataCadastro, isNotNull);
    });

    test('rejeita senha incorreta de usuario PBKDF2', () async {
      await repository.cadastrarUsuario(
        nome: 'Alex',
        email: 'alex@example.com',
        senha: 'abc12345',
      );

      final usuario = await repository.autenticarUsuario(
        email: 'alex@example.com',
        senha: 'senha-errada',
      );

      expect(usuario, isNull);
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
      expect(usuario.senhaHash, 'external_provider');
      expect(usuario.senhaSalt, isNull);
      expect(usuario.senhaAlgoritmo, 'external_provider');
      expect(usuario.senhaIteracoes, 0);
      expect(usuario.senhaVersao, 2);
    });

    test('usuario external_provider nao autentica com senha local', () async {
      await repository.autenticarComGoogle(
        nome: 'Alex Google',
        email: 'alex.google@example.com',
        googleId: 'google-123',
      );

      final usuario = await repository.autenticarUsuario(
        email: 'alex.google@example.com',
        senha: 'qualquer-senha',
      );

      expect(usuario, isNull);
    });

    test(
      'vincula Google a usuario local existente sem remover senha',
      () async {
        await repository.cadastrarUsuario(
          nome: 'Alex Local',
          email: 'alex@example.com',
          senha: 'abc12345',
        );
        final localAntes = await repository.buscarPorEmail('alex@example.com');

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
        expect(vinculado.senhaHash, localAntes!.senhaHash);
        expect(vinculado.senhaSalt, localAntes.senhaSalt);
        expect(vinculado.senhaAlgoritmo, localAntes.senhaAlgoritmo);
        expect(vinculado.senhaIteracoes, localAntes.senhaIteracoes);
        expect(vinculado.senhaVersao, localAntes.senhaVersao);
        expect(loginLocal, isNotNull);
        expect(loginLocal!.googleId, 'google-456');
      },
    );

    test('usuario legado sha256 autentica e migra para PBKDF2', () async {
      await _inserirUsuarioLegado(
        email: 'legado@example.com',
        senhaHash: repository.gerarHashSenha('abc12345'),
      );

      final usuario = await repository.autenticarUsuario(
        email: 'legado@example.com',
        senha: 'abc12345',
      );

      expect(usuario, isNotNull);
      expect(usuario!.senhaAlgoritmo, 'pbkdf2_sha256');
      expect(usuario.senhaSalt, isNotNull);
      expect(usuario.senhaIteracoes, 120000);
      expect(usuario.senhaVersao, 2);
      expect(usuario.senhaHash, isNot(repository.gerarHashSenha('abc12345')));
    });

    test(
      'usuario legado sha256 usa senha trimada na migracao progressiva',
      () async {
        await _inserirUsuarioLegado(
          email: 'legado@example.com',
          senhaHash: repository.gerarHashSenha('abc12345'),
        );

        final usuario = await repository.autenticarUsuario(
          email: 'legado@example.com',
          senha: ' abc12345 ',
        );

        expect(usuario, isNotNull);
        expect(usuario!.senhaAlgoritmo, 'pbkdf2_sha256');

        final loginMigrado = await repository.autenticarUsuario(
          email: 'legado@example.com',
          senha: 'abc12345',
        );
        expect(loginMigrado, isNotNull);
      },
    );

    test('usuario legado sha256 com senha errada nao migra', () async {
      await _inserirUsuarioLegado(
        email: 'legado@example.com',
        senhaHash: repository.gerarHashSenha('abc12345'),
      );

      final usuario = await repository.autenticarUsuario(
        email: 'legado@example.com',
        senha: 'senha-errada',
      );
      final legado = await repository.buscarPorEmail('legado@example.com');

      expect(usuario, isNull);
      expect(legado!.senhaAlgoritmo, 'sha256_legacy');
      expect(legado.senhaSalt, isNull);
      expect(legado.senhaIteracoes, 0);
      expect(legado.senhaVersao, 1);
    });
  });
}

Future<void> _inserirUsuarioLegado({
  required String email,
  required String senhaHash,
}) async {
  final db = await AppDatabase.instance.database;
  await db.insert('usuario', {
    'nome': 'Legado',
    'email': email,
    'senha_hash': senhaHash,
    'senha_algoritmo': 'sha256_legacy',
    'senha_iteracoes': 0,
    'senha_versao': 1,
  });
}
