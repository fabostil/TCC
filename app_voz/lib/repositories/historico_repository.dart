import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/tables/historico_acao_table.dart';
import '../models/dashboard_action_metric.dart';
import '../models/historico_acao.dart';

class HistoricoRepository {
  HistoricoRepository._internal();

  static final HistoricoRepository instance = HistoricoRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<int> registrarAcao(HistoricoAcao historico) async {
    final db = await _database;

    return db.insert(
      HistoricoAcaoTable.tableName,
      historico.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> registrar({
    required int usuarioId,
    required String tipo,
    required String descricao,
    int? gravacaoId,
    int? projetoId,
    DateTime? dataHora,
  }) {
    final historico = HistoricoAcao(
      usuarioId: usuarioId,
      gravacaoId: gravacaoId,
      projetoId: projetoId,
      tipo: tipo.trim(),
      descricao: descricao.trim(),
      dataHora: (dataHora ?? DateTime.now()).toIso8601String(),
    );

    return registrarAcao(historico);
  }

  Future<List<HistoricoAcao>> listarPorUsuario(
    int usuarioId, {
    int? limite,
  }) async {
    final db = await _database;

    final resultado = await db.query(
      HistoricoAcaoTable.tableName,
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'data_hora DESC',
      limit: limite,
    );

    return resultado.map(HistoricoAcao.fromMap).toList();
  }

  Future<List<HistoricoAcao>> listarPorGravacao(int gravacaoId) async {
    final db = await _database;

    final resultado = await db.query(
      HistoricoAcaoTable.tableName,
      where: 'gravacao_id = ?',
      whereArgs: [gravacaoId],
      orderBy: 'data_hora DESC',
    );

    return resultado.map(HistoricoAcao.fromMap).toList();
  }

  Future<List<HistoricoAcao>> listarPorProjeto(int projetoId) async {
    final db = await _database;

    final resultado = await db.query(
      HistoricoAcaoTable.tableName,
      where: 'projeto_id = ?',
      whereArgs: [projetoId],
      orderBy: 'data_hora DESC',
    );

    return resultado.map(HistoricoAcao.fromMap).toList();
  }

  Future<int> contarPorTipo({
    required int usuarioId,
    required String tipo,
  }) async {
    final db = await _database;
    final resultado = await db.rawQuery(
      '''
        SELECT COUNT(*) AS total
        FROM ${HistoricoAcaoTable.tableName}
        WHERE usuario_id = ? AND tipo = ?
      ''',
      [usuarioId, tipo],
    );

    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<List<DashboardActionMetric>> contarAcoesPorTipo(int usuarioId) async {
    final db = await _database;
    final resultado = await db.rawQuery(
      '''
        SELECT tipo, COUNT(*) AS total
        FROM ${HistoricoAcaoTable.tableName}
        WHERE usuario_id = ?
        GROUP BY tipo
        ORDER BY total DESC, tipo ASC
      ''',
      [usuarioId],
    );

    return resultado.map((linha) {
      return DashboardActionMetric(
        tipo: linha['tipo'] as String,
        total: linha['total'] as int,
      );
    }).toList();
  }
}
