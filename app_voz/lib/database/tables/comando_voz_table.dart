class ComandoVozTable {
  static const String tableName = 'comando_voz';

  static const String createTable =
      '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      texto_reconhecido TEXT NOT NULL,
      tipo_comando TEXT NOT NULL,
      status_reconhecimento TEXT NOT NULL,
      acao_executada TEXT,
      data_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
    )
  ''';

  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_comando_voz_usuario_id ON comando_voz(usuario_id)',
    'CREATE INDEX IF NOT EXISTS idx_comando_voz_tipo_comando ON comando_voz(tipo_comando)',
    'CREATE INDEX IF NOT EXISTS idx_comando_voz_data_hora ON comando_voz(data_hora)',
  ];
}
