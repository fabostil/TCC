import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/tables/gravacao_table.dart';
import '../models/gravacao.dart';

class GravacaoRepository {
  GravacaoRepository._internal();

  static final GravacaoRepository instance = GravacaoRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<int> criarGravacao(Gravacao gravacao) async {
    final db = await _database;
    return db.insert(
      GravacaoTable.tableName,
      gravacao.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Gravacao>> listarGravacoesPorUsuario(int usuarioId) async {
    final db = await _database;

    final resultado = await db.query(
      GravacaoTable.tableName,
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(Gravacao.fromMap).toList();
  }

  Future<List<Gravacao>> listarGravacoesPorProjeto(int projetoId) async {
    final db = await _database;

    final resultado = await db.query(
      GravacaoTable.tableName,
      where: 'projeto_id = ?',
      whereArgs: [projetoId],
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(Gravacao.fromMap).toList();
  }

  Future<Gravacao?> buscarGravacaoPorId(int id) async {
    final db = await _database;

    final resultado = await db.query(
      GravacaoTable.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Gravacao.fromMap(resultado.first);
  }

  Future<int> atualizarGravacao(Gravacao gravacao) async {
    if (gravacao.id == null) {
      throw ArgumentError('Gravação sem id não pode ser atualizada.');
    }

    final db = await _database;

    return db.update(
      GravacaoTable.tableName,
      gravacao.toMap(),
      where: 'id = ?',
      whereArgs: [gravacao.id],
    );
  }

  Future<int> removerGravacao(int id) async {
    final db = await _database;
    return db.delete(
      GravacaoTable.tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
