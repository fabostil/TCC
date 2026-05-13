import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../database/tables/configuracao_app_table.dart';
import '../models/configuracao_app.dart';

class ConfiguracaoAppRepository {
  ConfiguracaoAppRepository._internal();

  static final ConfiguracaoAppRepository instance =
      ConfiguracaoAppRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  Future<ConfiguracaoApp> buscarConfiguracao() async {
    final db = await _database;
    await _garantirConfiguracaoPadrao(db);

    final resultado = await db.query(
      ConfiguracaoAppTable.tableName,
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return ConfiguracaoApp.padrao();
    }

    return ConfiguracaoApp.fromMap(resultado.first);
  }

  Future<void> salvarConfiguracao(ConfiguracaoApp configuracao) async {
    final db = await _database;
    await db.insert(
      ConfiguracaoAppTable.tableName,
      configuracao
          .copyWith(dataAtualizacao: DateTime.now().toIso8601String())
          .toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> concluirPrimeiraExecucao({
    required bool comandosVozAtivos,
  }) async {
    final configuracao = await buscarConfiguracao();

    await salvarConfiguracao(
      configuracao.copyWith(
        comandosVozAtivos: comandosVozAtivos,
        primeiraExecucaoConcluida: true,
      ),
    );
  }

  Future<void> atualizarComandosVoz(bool ativo) async {
    final configuracao = await buscarConfiguracao();
    await salvarConfiguracao(configuracao.copyWith(comandosVozAtivos: ativo));
  }

  Future<void> atualizarEscutaContinua(bool ativo) async {
    final configuracao = await buscarConfiguracao();
    await salvarConfiguracao(configuracao.copyWith(escutaContinua: ativo));
  }

  Future<void> atualizarFeedbackSonoro(bool ativo) async {
    final configuracao = await buscarConfiguracao();
    await salvarConfiguracao(configuracao.copyWith(feedbackSonoro: ativo));
  }

  Future<void> atualizarParadaSilencio(bool ativo) async {
    final configuracao = await buscarConfiguracao();
    await salvarConfiguracao(configuracao.copyWith(paradaSilencio: ativo));
  }

  Future<void> atualizarTempoSilencio(int segundos) async {
    final configuracao = await buscarConfiguracao();
    await salvarConfiguracao(
      configuracao.copyWith(tempoSilencioSegundos: segundos),
    );
  }

  Future<void> _garantirConfiguracaoPadrao(Database db) async {
    await db.execute(ConfiguracaoAppTable.insertDefault);
  }
}
