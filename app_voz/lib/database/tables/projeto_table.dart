class ProjetoTable {
  static const String tableName = 'projeto';

  static const String createTable = '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      nome TEXT NOT NULL,
      descricao TEXT,
      data_criacao TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
    )
  ''';

  static const List<String> indexes = [
    'CREATE INDEX idx_projeto_usuario_id ON projeto(usuario_id)',
    'CREATE INDEX idx_projeto_nome ON projeto(nome)',
  ];
}
