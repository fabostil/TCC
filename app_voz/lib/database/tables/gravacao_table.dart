class GravacaoTable {
  static const String tableName = 'gravacao';

  static const String createTable =
      '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      nome TEXT NOT NULL,
      caminho_arquivo TEXT NOT NULL,
      data_criacao TEXT NOT NULL,
      duracao_segundos INTEGER DEFAULT 0,
      motivo_parada TEXT,
      maior_pico REAL DEFAULT -160.0,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
    )
  ''';

  static const List<String> indexes = [
    'CREATE INDEX idx_gravacao_usuario_id ON gravacao(usuario_id)',
    'CREATE INDEX idx_gravacao_data_criacao ON gravacao(data_criacao)',
  ];
}
