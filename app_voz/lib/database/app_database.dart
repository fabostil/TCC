import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'tables/gravacao_table.dart';

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

    await db.execute(GravacaoTable.createTable);

    for (final index in GravacaoTable.indexes) {
      await db.execute(index);
    }

    await db.execute('''
      CREATE TABLE comando_voz (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        comando TEXT NOT NULL,
        acao_executada TEXT NOT NULL,
        data_execucao TEXT NOT NULL,
        FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS projeto');

      final tabelas = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='gravacao'",
      );

      if (tabelas.isEmpty) {
        await db.execute(GravacaoTable.createTable);
      } else {
        final colunas = await db.rawQuery('PRAGMA table_info(gravacao)');
        final nomesColunas = colunas.map((item) => item['name']).toSet();

        if (!nomesColunas.contains('motivo_parada')) {
          await db.execute('ALTER TABLE gravacao ADD COLUMN motivo_parada TEXT');
        }

        if (!nomesColunas.contains('maior_pico')) {
          await db.execute(
            'ALTER TABLE gravacao ADD COLUMN maior_pico REAL DEFAULT -160.0',
          );
        }
      }

      for (final index in GravacaoTable.indexes) {
        await db.execute(index.replaceFirst('CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
      }
    }
  }

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
