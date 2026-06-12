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
<<<<<<< HEAD
      motivo_parada TEXT,
      maior_pico REAL DEFAULT -160.0,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
=======
      status TEXT NOT NULL DEFAULT 'concluida'
        CHECK (status IN ('concluida', 'interrompida', 'arquivo_ausente', 'excluida')),
      tamanho_bytes INTEGER NOT NULL DEFAULT 0 CHECK (tamanho_bytes >= 0),
      formato_audio TEXT NOT NULL DEFAULT 'm4a',
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE,
      FOREIGN KEY (projeto_id) REFERENCES projeto(id) ON DELETE SET NULL
>>>>>>> feature/true-voice-first
    )
  ''';

  static const List<String> indexes = [
<<<<<<< HEAD
    'CREATE INDEX idx_gravacao_usuario_id ON gravacao(usuario_id)',
    'CREATE INDEX idx_gravacao_data_criacao ON gravacao(data_criacao)',
=======
    'CREATE INDEX IF NOT EXISTS idx_gravacao_usuario_id ON gravacao(usuario_id)',
    'CREATE INDEX IF NOT EXISTS idx_gravacao_projeto_id ON gravacao(projeto_id)',
    'CREATE INDEX IF NOT EXISTS idx_gravacao_data_criacao ON gravacao(data_criacao)',
    'CREATE INDEX IF NOT EXISTS idx_gravacao_status ON gravacao(status)',
    'CREATE INDEX IF NOT EXISTS idx_gravacao_nome ON gravacao(nome)',
>>>>>>> feature/true-voice-first
  ];
}
