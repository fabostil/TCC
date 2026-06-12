import 'package:app_voz/database/app_database.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/repository_test_utils.dart';

void main() {
  const databaseName = 'app_database_migration_test.db';

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    await resetRepositoryTestDatabase(databaseName);
  });

  tearDown(() async {
    await resetRepositoryTestDatabase(databaseName);
  });

  test(
    'migra banco legado v1 ate v9 preservando dados e integridade',
    () async {
      await _createLegacyV1Database(databaseName);

      await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
      final db = await AppDatabase.instance.database;

      final version = await db.getVersion();
      expect(version, 9);

      final usuario = await db.query('usuario', limit: 1);
      expect(usuario.single['email'], 'alex@example.com');
      expect(usuario.single['senha_salt'], isNull);
      expect(usuario.single['senha_algoritmo'], 'sha256_legacy');
      expect(usuario.single['senha_iteracoes'], 0);
      expect(usuario.single['senha_versao'], 1);
      expect(usuario.single['auth_provider'], 'local');
      expect(usuario.single['google_id'], isNull);

      final gravacao = await db.query('gravacao', limit: 1);
      expect(gravacao.single['nome'], 'Refrao antigo');
      expect(gravacao.single['projeto_id'], isNull);
      expect(gravacao.single['status'], 'concluida');
      expect(gravacao.single['tamanho_bytes'], 0);
      expect(gravacao.single['formato_audio'], 'm4a');

      final comando = await db.query('comando_voz', limit: 1);
      expect(comando.single['texto_reconhecido'], 'iniciar gravacao');
      expect(comando.single['tipo_comando'], 'legacy');
      expect(comando.single['status_reconhecimento'], 'reconhecido');

      final configuracao = await db.query('configuracao_app', limit: 1);
      expect(configuracao.single['escuta_continua'], 1);
      expect(configuracao.single['tema_escuro'], 0);

      await db.insert('projeto', {
        'usuario_id': usuario.single['id'],
        'nome': 'Projeto FK',
        'descricao': 'Teste de integridade',
        'data_criacao': '2026-05-19T10:00:00.000',
      });
      final projeto = await db.query('projeto', limit: 1);

      final gravacaoComProjetoId = await db.insert('gravacao', {
        'usuario_id': usuario.single['id'],
        'projeto_id': projeto.single['id'],
        'nome': 'Com vinculo',
        'caminho_arquivo': '/tmp/com-vinculo.m4a',
        'data_criacao': '2026-05-19T11:00:00.000',
        'duracao_segundos': 3,
        'status': 'concluida',
        'tamanho_bytes': 256,
        'formato_audio': 'm4a',
      });

      await db.delete(
        'projeto',
        where: 'id = ?',
        whereArgs: [projeto.single['id']],
      );
      final gravacaoSemProjeto = await db.query(
        'gravacao',
        where: 'id = ?',
        whereArgs: [gravacaoComProjetoId],
        limit: 1,
      );
      expect(gravacaoSemProjeto.single['projeto_id'], isNull);

      await db.delete(
        'usuario',
        where: 'id = ?',
        whereArgs: [usuario.single['id']],
      );
      expect(await db.query('gravacao'), isEmpty);
      expect(await db.query('comando_voz'), isEmpty);
    },
  );

  test('schema v9 rejeita status e tamanho invalidos de gravacao', () async {
    await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
    final db = await AppDatabase.instance.database;

    final usuarioId = await db.insert('usuario', {
      'nome': 'Alex',
      'email': 'alex-hard@example.com',
      'senha_hash': 'hash',
    });

    expect(
      () => db.insert('gravacao', {
        'usuario_id': usuarioId,
        'nome': 'Status invalido',
        'caminho_arquivo': '/tmp/status.m4a',
        'data_criacao': '2026-05-19T10:00:00.000',
        'status': 'qualquer',
      }),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      () => db.insert('gravacao', {
        'usuario_id': usuarioId,
        'nome': 'Tamanho invalido',
        'caminho_arquivo': '/tmp/tamanho.m4a',
        'data_criacao': '2026-05-19T10:00:00.000',
        'tamanho_bytes': -1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('schema v9 cria colunas de senha no banco novo', () async {
    await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
    final db = await AppDatabase.instance.database;

    final columns = await db.rawQuery('PRAGMA table_info(usuario)');
    final columnNames = columns.map((column) => column['name']).toSet();

    expect(columnNames, contains('senha_salt'));
    expect(columnNames, contains('senha_algoritmo'));
    expect(columnNames, contains('senha_iteracoes'));
    expect(columnNames, contains('senha_versao'));
  });

  test('migra usuarios Google exclusivos para provedor externo', () async {
    await _createLegacyV8Database(databaseName);

    await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
    final db = await AppDatabase.instance.database;

    expect(await db.getVersion(), 9);

    final google = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: ['google@example.com'],
      limit: 1,
    );
    expect(google.single['senha_hash'], 'external_provider');
    expect(google.single['senha_salt'], isNull);
    expect(google.single['senha_algoritmo'], 'external_provider');
    expect(google.single['senha_iteracoes'], 0);
    expect(google.single['senha_versao'], 2);

    final local = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: ['local@example.com'],
      limit: 1,
    );
    expect(local.single['senha_hash'], 'local_hash');
    expect(local.single['senha_algoritmo'], 'sha256_legacy');

    final localGoogle = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: ['local-google@example.com'],
      limit: 1,
    );
    expect(localGoogle.single['senha_hash'], 'local_google_hash');
    expect(localGoogle.single['senha_algoritmo'], 'sha256_legacy');
  });

  test('migration autorizada adiciona coluna quando ela nao existe', () async {
    await _createLegacyV8Database(databaseName);

    await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
    final db = await AppDatabase.instance.database;

    final columns = await db.rawQuery('PRAGMA table_info(usuario)');
    final columnNames = columns.map((column) => column['name']).toSet();

    expect(columnNames, contains('senha_salt'));
    expect(columnNames, contains('senha_algoritmo'));
    expect(columnNames, contains('senha_iteracoes'));
    expect(columnNames, contains('senha_versao'));
  });

  test('migration autorizada e idempotente quando coluna ja existe', () async {
    await _createLegacyV8DatabaseWithPasswordColumns(databaseName);

    await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
    final db = await AppDatabase.instance.database;

    expect(await db.getVersion(), 9);

    final usuario = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: ['local@example.com'],
      limit: 1,
    );
    expect(usuario.single['senha_salt'], isNull);
    expect(usuario.single['senha_algoritmo'], 'sha256_legacy');
    expect(usuario.single['senha_iteracoes'], 0);
    expect(usuario.single['senha_versao'], 1);
  });

  test('whitelist bloqueia tabela e coluna nao autorizadas', () {
    expect(
      () => AppDatabase.instance.validateAllowedMigrationColumnForTesting(
        tableName: 'usuario',
        columnName: 'senha_texto_puro',
        definition: 'TEXT',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'Unauthorized migration column: usuario.senha_texto_puro',
        ),
      ),
    );
  });

  test('whitelist bloqueia definicao SQL diferente da autorizada', () {
    expect(
      () => AppDatabase.instance.validateAllowedMigrationColumnForTesting(
        tableName: 'usuario',
        columnName: 'senha_algoritmo',
        definition: "TEXT NOT NULL DEFAULT 'pbkdf2_sha256'",
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'Unauthorized migration definition for usuario.senha_algoritmo',
        ),
      ),
    );
  });
}

Future<void> _createLegacyV1Database(String databaseName) async {
  final path = join(await getDatabasesPath(), databaseName);
  final db = await openDatabase(
    path,
    version: 1,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, _) async {
      await database.execute('''
        CREATE TABLE usuario (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          senha_hash TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE gravacao (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          usuario_id INTEGER NOT NULL,
          nome TEXT NOT NULL,
          caminho_arquivo TEXT NOT NULL,
          data_criacao TEXT NOT NULL,
          duracao_segundos INTEGER DEFAULT 0,
          FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
        )
      ''');
      await database.execute('''
        CREATE TABLE comando_voz (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          usuario_id INTEGER NOT NULL,
          comando TEXT NOT NULL,
          acao_executada TEXT,
          data_execucao TEXT NOT NULL,
          FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
        )
      ''');
    },
  );

  final usuarioId = await db.insert('usuario', {
    'nome': 'Alex',
    'email': 'alex@example.com',
    'senha_hash': 'hash',
  });

  await db.insert('gravacao', {
    'usuario_id': usuarioId,
    'nome': 'Refrao antigo',
    'caminho_arquivo': '/tmp/refrao-antigo.m4a',
    'data_criacao': '2026-05-18T10:00:00.000',
    'duracao_segundos': 42,
  });

  await db.insert('comando_voz', {
    'usuario_id': usuarioId,
    'comando': 'iniciar gravacao',
    'acao_executada': 'iniciar_gravacao',
    'data_execucao': '2026-05-18T10:01:00.000',
  });

  await db.close();
}

Future<void> _createLegacyV8Database(String databaseName) async {
  final path = join(await getDatabasesPath(), databaseName);
  final db = await openDatabase(
    path,
    version: 8,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, _) async {
      await database.execute('''
        CREATE TABLE usuario (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          senha_hash TEXT NOT NULL,
          auth_provider TEXT NOT NULL DEFAULT 'local',
          google_id TEXT UNIQUE,
          foto_url TEXT,
          data_cadastro TEXT
        )
      ''');
    },
  );

  await db.insert('usuario', {
    'nome': 'Google',
    'email': 'google@example.com',
    'senha_hash': 'old_google_hash',
    'auth_provider': 'google',
    'google_id': 'google-123',
  });
  await db.insert('usuario', {
    'nome': 'Local',
    'email': 'local@example.com',
    'senha_hash': 'local_hash',
    'auth_provider': 'local',
  });
  await db.insert('usuario', {
    'nome': 'Local Google',
    'email': 'local-google@example.com',
    'senha_hash': 'local_google_hash',
    'auth_provider': 'local_google',
    'google_id': 'google-456',
  });

  await db.close();
}

Future<void> _createLegacyV8DatabaseWithPasswordColumns(
  String databaseName,
) async {
  final path = join(await getDatabasesPath(), databaseName);
  final db = await openDatabase(
    path,
    version: 8,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, _) async {
      await database.execute('''
        CREATE TABLE usuario (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          senha_hash TEXT NOT NULL,
          auth_provider TEXT NOT NULL DEFAULT 'local',
          google_id TEXT UNIQUE,
          foto_url TEXT,
          data_cadastro TEXT,
          senha_salt TEXT,
          senha_algoritmo TEXT NOT NULL DEFAULT 'sha256_legacy',
          senha_iteracoes INTEGER NOT NULL DEFAULT 0,
          senha_versao INTEGER NOT NULL DEFAULT 1
        )
      ''');
    },
  );

  await db.insert('usuario', {
    'nome': 'Local',
    'email': 'local@example.com',
    'senha_hash': 'local_hash',
    'auth_provider': 'local',
  });

  await db.close();
}
