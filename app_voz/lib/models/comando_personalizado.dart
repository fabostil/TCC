class ComandoPersonalizado {
  const ComandoPersonalizado({
    this.id,
    required this.usuarioId,
    required this.frase,
    required this.tipoComando,
    required this.ativo,
    required this.dataCriacao,
  });

  final int? id;
  final int usuarioId;
  final String frase;
  final String tipoComando;
  final bool ativo;
  final String dataCriacao;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'frase': frase,
      'tipo_comando': tipoComando,
      'ativo': ativo ? 1 : 0,
      'data_criacao': dataCriacao,
    };
  }

  factory ComandoPersonalizado.fromMap(Map<String, dynamic> map) {
    return ComandoPersonalizado(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      frase: map['frase'] as String,
      tipoComando: map['tipo_comando'] as String,
      ativo: (map['ativo'] as int) == 1,
      dataCriacao: map['data_criacao'] as String,
    );
  }

  ComandoPersonalizado copyWith({
    int? id,
    int? usuarioId,
    String? frase,
    String? tipoComando,
    bool? ativo,
    String? dataCriacao,
  }) {
    return ComandoPersonalizado(
      id: id ?? this.id,
      usuarioId: usuarioId ?? this.usuarioId,
      frase: frase ?? this.frase,
      tipoComando: tipoComando ?? this.tipoComando,
      ativo: ativo ?? this.ativo,
      dataCriacao: dataCriacao ?? this.dataCriacao,
    );
  }
}
