import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'tables/comando_voz_table.dart';
import 'tables/comando_personalizado_table.dart';
import 'tables/configuracao_app_table.dart';
import 'tables/gravacao_table.dart';
import 'tables/historico_acao_table.dart';
import 'tables/projeto_table.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  static const Set<String> _allowedMigrationColumns = {
    'configuracao_app.tema_escuro',
    'usuario.auth_provider',
    'usuario.google_id',
    'usuario.foto_url',
    'usuario.data_cadastro',
    'usuario.senha_salt',
    'usuario.senha_algoritmo',
    'usuario.senha_iteracoes',
    'usuario.senha_versao',
    'gravacao.status',
    'gravacao.tamanho_bytes',
    'gravacao.formato_audio',
  };

  static const Map<String, String> _allowedMigrationDefinitions = {
    'configuracao_app.tema_escuro': 'INTEGER NOT NULL DEFAULT 0',
    'usuario.auth_provider': "TEXT NOT NULL DEFAULT 'local'",
    'usuario.google_id': 'TEXT',
    'usuario.foto_url': 'TEXT',
    'usuario.data_cadastro': 'TEXT',
    'usuario.senha_salt': 'TEXT',
    'usuario.senha_algoritmo': "TEXT NOT NULL DEFAULT 'sha256_legacy'",
    'usuario.senha_iteracoes': 'INTEGER NOT NULL DEFAULT 0',
    'usuario.senha_versao': 'INTEGER NOT NULL DEFAULT 1',
    'gravacao.status':
        "TEXT NOT NULL DEFAULT 'concluida' "
        "CHECK (status IN ('concluida', 'interrompida', "
        "'arquivo_ausente', 'excluida'))",
    'gravacao.tamanho_bytes':
        'INTEGER NOT NULL DEFAULT 0 CHECK (tamanho_bytes >= 0)',
    'gravacao.formato_audio': "TEXT NOT NULL DEFAULT 'm4a'",
  };

  Database? _database;
  String _databaseName = 'assistente_musical.db';

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, _databaseName);

    return openDatabase(
      path,
      version: 9,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        senha_hash TEXT NOT NULL,
        senha_salt TEXT,
        senha_algoritmo TEXT NOT NULL DEFAULT 'sha256_legacy',
        senha_iteracoes INTEGER NOT NULL DEFAULT 0,
        senha_versao INTEGER NOT NULL DEFAULT 1,
        auth_provider TEXT NOT NULL DEFAULT 'local',
        google_id TEXT UNIQUE,
        foto_url TEXT,
        data_cadastro TEXT
      )
    ''');

    await db.execute(ProjetoTable.createTable);
    await db.execute(GravacaoTable.createTable);
    await db.execute(ComandoVozTable.createTable);
    await db.execute(ComandoPersonalizadoTable.createTable);
    await db.execute(HistoricoAcaoTable.createTable);
    await db.execute(ConfiguracaoAppTable.createTable);
    await db.execute(ConfiguracaoAppTable.insertDefault);

    for (final index in ProjetoTable.indexes) {
      await db.execute(index);
    }

    for (final index in GravacaoTable.indexes) {
      await db.execute(index);
    }

    for (final index in ComandoVozTable.indexes) {
      await db.execute(index);
    }

    for (final index in ComandoPersonalizadoTable.indexes) {
      await db.execute(index);
    }

    for (final index in HistoricoAcaoTable.indexes) {
      await db.execute(index);
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_usuario_google_id '
      'ON usuario(google_id) WHERE google_id IS NOT NULL',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(ProjetoTable.createTable);

      await db.execute('ALTER TABLE gravacao RENAME TO gravacao_legacy');
      await db.execute(GravacaoTable.createTable);

      await db.execute('''
        INSERT INTO gravacao (
          id,
          usuario_id,
          projeto_id,
          nome,
          caminho_arquivo,
          data_criacao,
          duracao_segundos
        )
        SELECT
          id,
          usuario_id,
          NULL,
          nome,
          caminho_arquivo,
          data_criacao,
          duracao_segundos
        FROM gravacao_legacy
      ''');

      await db.execute('DROP TABLE gravacao_legacy');

      for (final index in ProjetoTable.indexes) {
        await db.execute(index);
      }

      for (final index in GravacaoTable.indexes) {
        await db.execute(index);
      }
    }

    if (oldVersion < 3) {
      await _migrateComandoVozToVersion3(db);
      await db.execute(HistoricoAcaoTable.createTable);

      for (final index in ComandoVozTable.indexes) {
        await db.execute(index);
      }

      for (final index in HistoricoAcaoTable.indexes) {
        await db.execute(index);
      }
    }

    if (oldVersion < 4) {
      await db.execute(ConfiguracaoAppTable.createTable);
      await db.execute(ConfiguracaoAppTable.insertDefault);
    }

    if (oldVersion < 5) {
      await db.execute(ConfiguracaoAppTable.createTable);
      await _addColumnIfMissing(
        db,
        tableName: ConfiguracaoAppTable.tableName,
        columnName: 'tema_escuro',
        definition: 'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(ConfiguracaoAppTable.insertDefault);
    }

    if (oldVersion < 6) {
      await db.execute(ComandoPersonalizadoTable.createTable);

      for (final index in ComandoPersonalizadoTable.indexes) {
        await db.execute(index);
      }
    }

    if (oldVersion < 7) {
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'auth_provider',
        definition: "TEXT NOT NULL DEFAULT 'local'",
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'google_id',
        definition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'foto_url',
        definition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'data_cadastro',
        definition: 'TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_usuario_google_id '
        'ON usuario(google_id) WHERE google_id IS NOT NULL',
      );
    }

    if (oldVersion < 8) {
      await _addColumnIfMissing(
        db,
        tableName: GravacaoTable.tableName,
        columnName: 'status',
        definition:
            "TEXT NOT NULL DEFAULT 'concluida' "
            "CHECK (status IN ('concluida', 'interrompida', "
            "'arquivo_ausente', 'excluida'))",
      );
      await _addColumnIfMissing(
        db,
        tableName: GravacaoTable.tableName,
        columnName: 'tamanho_bytes',
        definition: 'INTEGER NOT NULL DEFAULT 0 CHECK (tamanho_bytes >= 0)',
      );
      await _addColumnIfMissing(
        db,
        tableName: GravacaoTable.tableName,
        columnName: 'formato_audio',
        definition: "TEXT NOT NULL DEFAULT 'm4a'",
      );

      for (final index in GravacaoTable.indexes) {
        await db.execute(index);
      }
    }

    if (oldVersion < 9) {
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'senha_salt',
        definition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'senha_algoritmo',
        definition: "TEXT NOT NULL DEFAULT 'sha256_legacy'",
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'senha_iteracoes',
        definition: 'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'usuario',
        columnName: 'senha_versao',
        definition: 'INTEGER NOT NULL DEFAULT 1',
      );

      await db.update(
        'usuario',
        {
          'senha_hash': 'external_provider',
          'senha_salt': null,
          'senha_algoritmo': 'external_provider',
          'senha_iteracoes': 0,
          'senha_versao': 2,
        },
        where: 'auth_provider = ? AND google_id IS NOT NULL',
        whereArgs: ['google'],
      );
    }
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    validateAllowedMigrationColumnForTesting(
      tableName: tableName,
      columnName: columnName,
      definition: definition,
    );

    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains(columnName)) {
      return;
    }

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  @visibleForTesting
  void validateAllowedMigrationColumnForTesting({
    required String tableName,
    required String columnName,
    required String definition,
  }) {
    final migrationKey = '$tableName.$columnName';

    if (!_allowedMigrationColumns.contains(migrationKey)) {
      throw ArgumentError('Unauthorized migration column: $migrationKey');
    }

    final allowedDefinition = _allowedMigrationDefinitions[migrationKey];
    if (allowedDefinition == null ||
        definition.trim() != allowedDefinition.trim()) {
      throw ArgumentError(
        'Unauthorized migration definition for $migrationKey',
      );
    }
  }

  Future<void> _migrateComandoVozToVersion3(Database db) async {
    final tables = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', ComandoVozTable.tableName],
      limit: 1,
    );

    if (tables.isEmpty) {
      await db.execute(ComandoVozTable.createTable);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info(${ComandoVozTable.tableName})',
    );
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains('texto_reconhecido')) {
      return;
    }

    await db.execute('ALTER TABLE comando_voz RENAME TO comando_voz_legacy');
    await db.execute(ComandoVozTable.createTable);
    await db.execute('''
      INSERT INTO comando_voz (
        id,
        usuario_id,
        texto_reconhecido,
        tipo_comando,
        status_reconhecimento,
        acao_executada,
        data_hora
      )
      SELECT
        id,
        usuario_id,
        comando,
        'legacy',
        'reconhecido',
        acao_executada,
        data_execucao
      FROM comando_voz_legacy
    ''');
    await db.execute('DROP TABLE comando_voz_legacy');
  }

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<void> setDatabaseNameForTesting(String databaseName) async {
    await close();
    _databaseName = databaseName;
  }
}
