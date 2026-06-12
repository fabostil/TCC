import 'package:sqflite/sqflite.dart';

import '../core/search/sql_search.dart';
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

  Future<List<Gravacao>> listarGravacoesPorUsuario(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    final db = await _database;
    final where = <String>['usuario_id = ?', 'status != ?'];
    final whereArgs = <Object?>[usuarioId, GravacaoStatus.excluida];

    if (SqlSearch.hasTerm(termoBusca)) {
      where.add('(nome LIKE ? ESCAPE ? OR formato_audio LIKE ? ESCAPE ?)');
      final pattern = SqlSearch.containsPattern(termoBusca!);
      whereArgs.addAll([pattern, r'\', pattern, r'\']);
    }

    if (status != null) {
      where.add('status = ?');
      whereArgs.add(status);
    }

    final resultado = await db.query(
      GravacaoTable.tableName,
      where: where.join(' AND '),
      whereArgs: whereArgs,
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

  Future<List<String>> listarCaminhosArquivosAtivos() async {
    final db = await _database;

    final resultado = await db.query(
      GravacaoTable.tableName,
      columns: ['caminho_arquivo'],
      where: 'status != ?',
      whereArgs: [GravacaoStatus.excluida],
    );

    return resultado
        .map((row) => row['caminho_arquivo'])
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
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
    return db.delete(GravacaoTable.tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> marcarComoExcluida(int id) async {
    final db = await _database;
    return db.update(
      GravacaoTable.tableName,
      {'status': GravacaoStatus.excluida},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
