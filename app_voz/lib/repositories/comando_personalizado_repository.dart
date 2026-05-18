import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/tables/comando_personalizado_table.dart';
import '../models/comando_personalizado.dart';

class ComandoPersonalizadoRepository {
  ComandoPersonalizadoRepository._internal();

  static final ComandoPersonalizadoRepository instance =
      ComandoPersonalizadoRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<int> salvar(ComandoPersonalizado comando) async {
    final db = await _database;

    return db.insert(
      ComandoPersonalizadoTable.tableName,
      comando.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ComandoPersonalizado>> listarPorUsuario(int usuarioId) async {
    final db = await _database;
    final resultado = await db.query(
      ComandoPersonalizadoTable.tableName,
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(ComandoPersonalizado.fromMap).toList();
  }

  Future<List<ComandoPersonalizado>> listarAtivosPorUsuario(
    int usuarioId,
  ) async {
    final db = await _database;
    final resultado = await db.query(
      ComandoPersonalizadoTable.tableName,
      where: 'usuario_id = ? AND ativo = ?',
      whereArgs: [usuarioId, 1],
      orderBy: 'data_criacao DESC',
    );

    return resultado.map(ComandoPersonalizado.fromMap).toList();
  }

  Future<void> alternarAtivo({required int id, required bool ativo}) async {
    final db = await _database;
    await db.update(
      ComandoPersonalizadoTable.tableName,
      {'ativo': ativo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> excluir(int id) async {
    final db = await _database;
    await db.delete(
      ComandoPersonalizadoTable.tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
