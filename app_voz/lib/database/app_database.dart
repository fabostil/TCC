import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'tables/comando_voz_table.dart';
import 'tables/gravacao_table.dart';
import 'tables/historico_acao_table.dart';
import 'tables/projeto_table.dart';

class AppDatabase {
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'assistente_musical.db');

    return openDatabase(
      path,
      version: 3,
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
        senha_hash TEXT NOT NULL
      )
    ''');

    await db.execute(ProjetoTable.createTable);
    await db.execute(GravacaoTable.createTable);
    await db.execute(ComandoVozTable.createTable);
    await db.execute(HistoricoAcaoTable.createTable);

    for (final index in ProjetoTable.indexes) {
      await db.execute(index);
    }

    for (final index in GravacaoTable.indexes) {
      await db.execute(index);
    }

    for (final index in ComandoVozTable.indexes) {
      await db.execute(index);
    }

    for (final index in HistoricoAcaoTable.indexes) {
      await db.execute(index);
    }
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
}
