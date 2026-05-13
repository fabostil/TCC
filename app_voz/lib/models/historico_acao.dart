class HistoricoAcao {
  final int? id;
  final int usuarioId;
  final int? gravacaoId;
  final int? projetoId;
  final String tipo;
  final String descricao;
  final String dataHora;

  HistoricoAcao({
    this.id,
    required this.usuarioId,
    this.gravacaoId,
    this.projetoId,
    required this.tipo,
    required this.descricao,
    required this.dataHora,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'gravacao_id': gravacaoId,
      'projeto_id': projetoId,
      'tipo': tipo,
      'descricao': descricao,
      'data_hora': dataHora,
    };
  }

  factory HistoricoAcao.fromMap(Map<String, dynamic> map) {
    return HistoricoAcao(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      gravacaoId: map['gravacao_id'] as int?,
      projetoId: map['projeto_id'] as int?,
      tipo: map['tipo'] as String,
      descricao: map['descricao'] as String,
      dataHora: map['data_hora'] as String,
    );
  }
}
