class Projeto {
  final int? id;
  final int usuarioId;
  final String nome;
  final String? descricao;
  final String dataCriacao;

  Projeto({
    this.id,
    required this.usuarioId,
    required this.nome,
    this.descricao,
    required this.dataCriacao,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'nome': nome,
      'descricao': descricao,
      'data_criacao': dataCriacao,
    };
  }

  factory Projeto.fromMap(Map<String, dynamic> map) {
    return Projeto(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      dataCriacao: map['data_criacao'] as String,
    );
  }
}
