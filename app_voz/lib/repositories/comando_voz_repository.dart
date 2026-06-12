import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/tables/comando_voz_table.dart';
import '../models/comando_voz.dart';

class ComandoVozRepository {
  ComandoVozRepository._internal();

  static final ComandoVozRepository instance = ComandoVozRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<int> registrarComando(ComandoVoz comando) async {
    final db = await _database;

    return db.insert(
      ComandoVozTable.tableName,
      comando.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> registrar({
    required int usuarioId,
    required String textoReconhecido,
    required String tipoComando,
    required String statusReconhecimento,
    String? acaoExecutada,
    DateTime? dataHora,
  }) {
    final comando = ComandoVoz(
      usuarioId: usuarioId,
      textoReconhecido: textoReconhecido.trim(),
      tipoComando: tipoComando.trim(),
      statusReconhecimento: statusReconhecimento.trim(),
      acaoExecutada: acaoExecutada?.trim(),
      dataHora: (dataHora ?? DateTime.now()).toIso8601String(),
    );

    return registrarComando(comando);
  }

  Future<List<ComandoVoz>> listarPorUsuario(
    int usuarioId, {
    int? limite,
  }) async {
    final db = await _database;

    final resultado = await db.query(
      ComandoVozTable.tableName,
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_hora DESC',
      limit: limite,
    );

    return resultado.map(ComandoVoz.fromMap).toList();
  }

  Future<int> contarPorUsuario(int usuarioId) async {
    final db = await _database;
    final resultado = await db.rawQuery(
      '''
        SELECT COUNT(*) AS total
        FROM ${ComandoVozTable.tableName}
        WHERE usuario_id = ?
      ''',
      [usuarioId],
    );

    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> contarPorStatus({
    required int usuarioId,
    required String statusReconhecimento,
  }) async {
    final db = await _database;
    final resultado = await db.rawQuery(
      '''
        SELECT COUNT(*) AS total
        FROM ${ComandoVozTable.tableName}
        WHERE usuario_id = ? AND status_reconhecimento = ?
      ''',
      [usuarioId, statusReconhecimento],
    );

    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}
