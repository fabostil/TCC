import 'package:sqflite/sqflite.dart';

import '../core/search/sql_search.dart';
import '../database/app_database.dart';
import '../database/tables/projeto_table.dart';
import '../models/projeto.dart';

class ProjetoRepository {
  ProjetoRepository._internal();

  static final ProjetoRepository instance = ProjetoRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<int> criarProjeto(Projeto projeto) async {
    final db = await _database;
    return db.insert(
      ProjetoTable.tableName,
      projeto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Projeto>> listarProjetosPorUsuario(
    int usuarioId, {
    String? termoBusca,
  }) async {
    final db = await _database;
    final where = <String>['usuario_id = ?'];
    final whereArgs = <Object?>[usuarioId];

    if (SqlSearch.hasTerm(termoBusca)) {
      final pattern = SqlSearch.containsPattern(termoBusca!);
      where.add('(nome LIKE ? ESCAPE ? OR descricao LIKE ? ESCAPE ?)');
      whereArgs.addAll([pattern, r'\', pattern, r'\']);
    }

    final resultado = await db.query(
      ProjetoTable.tableName,
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(Projeto.fromMap).toList();
  }

  Future<Projeto?> buscarProjetoPorId(int id) async {
    final db = await _database;

    final resultado = await db.query(
      ProjetoTable.tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Projeto.fromMap(resultado.first);
  }

  Future<int> atualizarProjeto(Projeto projeto) async {
    if (projeto.id == null) {
      throw ArgumentError('Projeto sem id não pode ser atualizado.');
    }

    final db = await _database;

    return db.update(
      ProjetoTable.tableName,
      projeto.toMap(),
      where: 'id = ?',
      whereArgs: [projeto.id],
    );
  }

  Future<int> removerProjeto(int id) async {
    final db = await _database;
    return db.delete(ProjetoTable.tableName, where: 'id = ?', whereArgs: [id]);
  }
}
