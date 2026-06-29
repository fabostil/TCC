class ComandoPersonalizadoTable {
  static const String tableName = 'comando_personalizado';

  static const String createTable =
      '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      frase TEXT NOT NULL,
      tipo_comando TEXT NOT NULL,
      ativo INTEGER NOT NULL DEFAULT 1,
      data_criacao TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE,
      UNIQUE(usuario_id, frase)
    )
  ''';

  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_comando_personalizado_usuario_id ON comando_personalizado(usuario_id)',
    'CREATE INDEX IF NOT EXISTS idx_comando_personalizado_frase ON comando_personalizado(frase)',
    'CREATE INDEX IF NOT EXISTS idx_comando_personalizado_tipo ON comando_personalizado(tipo_comando)',
  ];
}
