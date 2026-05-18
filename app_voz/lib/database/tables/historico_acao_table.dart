class HistoricoAcaoTable {
  static const String tableName = 'historico_acao';

  static const String createTable =
      '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      gravacao_id INTEGER,
      projeto_id INTEGER,
      tipo TEXT NOT NULL,
      descricao TEXT NOT NULL,
      data_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE,
      FOREIGN KEY (gravacao_id) REFERENCES gravacao(id) ON DELETE SET NULL,
      FOREIGN KEY (projeto_id) REFERENCES projeto(id) ON DELETE SET NULL
    )
  ''';

  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_historico_acao_usuario_id ON historico_acao(usuario_id)',
    'CREATE INDEX IF NOT EXISTS idx_historico_acao_gravacao_id ON historico_acao(gravacao_id)',
    'CREATE INDEX IF NOT EXISTS idx_historico_acao_projeto_id ON historico_acao(projeto_id)',
    'CREATE INDEX IF NOT EXISTS idx_historico_acao_tipo ON historico_acao(tipo)',
    'CREATE INDEX IF NOT EXISTS idx_historico_acao_data_hora ON historico_acao(data_hora)',
  ];
}
