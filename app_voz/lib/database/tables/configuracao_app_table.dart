class ConfiguracaoAppTable {
  static const String tableName = 'configuracao_app';

  static const String createTable =
      '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      comandos_voz_ativos INTEGER NOT NULL DEFAULT 1,
      primeira_execucao_concluida INTEGER NOT NULL DEFAULT 0,
      escuta_continua INTEGER NOT NULL DEFAULT 0,
      feedback_sonoro INTEGER NOT NULL DEFAULT 0,
      parada_silencio INTEGER NOT NULL DEFAULT 1,
      tempo_silencio_segundos INTEGER NOT NULL DEFAULT 6,
      tema_escuro INTEGER NOT NULL DEFAULT 0,
      data_atualizacao TEXT NOT NULL
    )
  ''';

  static const String insertDefault =
      '''
    INSERT OR IGNORE INTO $tableName (
      id,
      comandos_voz_ativos,
      primeira_execucao_concluida,
      escuta_continua,
      feedback_sonoro,
      parada_silencio,
      tempo_silencio_segundos,
      tema_escuro,
      data_atualizacao
    ) VALUES (
      1,
      1,
      0,
      0,
      0,
      1,
      6,
      0,
      CURRENT_TIMESTAMP
    )
  ''';
}
