class Gravacao {
  final int? id;
  final int usuarioId;
  final int? projetoId;
  final String nome;
  final String caminhoArquivo;
  final String dataCriacao;
  final int duracaoSegundos;

  Gravacao({
    this.id,
    required this.usuarioId,
    this.projetoId,
    required this.nome,
    required this.caminhoArquivo,
    required this.dataCriacao,
    this.duracaoSegundos = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'projeto_id': projetoId,
      'nome': nome,
      'caminho_arquivo': caminhoArquivo,
      'data_criacao': dataCriacao,
      'duracao_segundos': duracaoSegundos,
    };
  }

  factory Gravacao.fromMap(Map<String, dynamic> map) {
    return Gravacao(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      projetoId: map['projeto_id'] as int?,
      nome: map['nome'] as String,
      caminhoArquivo: map['caminho_arquivo'] as String,
      dataCriacao: map['data_criacao'] as String,
      duracaoSegundos: (map['duracao_segundos'] as int?) ?? 0,
    );
  }
}
