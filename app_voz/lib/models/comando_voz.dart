class ComandoVoz {
  final int? id;
  final int usuarioId;
  final String textoReconhecido;
  final String tipoComando;
  final String statusReconhecimento;
  final String? acaoExecutada;
  final String dataHora;

  ComandoVoz({
    this.id,
    required this.usuarioId,
    required this.textoReconhecido,
    required this.tipoComando,
    required this.statusReconhecimento,
    this.acaoExecutada,
    required this.dataHora,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'texto_reconhecido': textoReconhecido,
      'tipo_comando': tipoComando,
      'status_reconhecimento': statusReconhecimento,
      'acao_executada': acaoExecutada,
      'data_hora': dataHora,
    };
  }

  factory ComandoVoz.fromMap(Map<String, dynamic> map) {
    return ComandoVoz(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      textoReconhecido: map['texto_reconhecido'] as String,
      tipoComando: map['tipo_comando'] as String,
      statusReconhecimento: map['status_reconhecimento'] as String,
      acaoExecutada: map['acao_executada'] as String?,
      dataHora: map['data_hora'] as String,
    );
  }
}
