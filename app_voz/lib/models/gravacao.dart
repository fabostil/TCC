class Gravacao {
  final int? id;
  final int usuarioId;
  final String nome;
  final String caminhoArquivo;
  final String dataCriacao;
  final int duracaoSegundos;
  final String? motivoParada;
  final double maiorPico;

  Gravacao({
    this.id,
    required this.usuarioId,
    required this.nome,
    required this.caminhoArquivo,
    required this.dataCriacao,
    this.duracaoSegundos = 0,
    this.motivoParada,
    this.maiorPico = -160.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'nome': nome,
      'caminho_arquivo': caminhoArquivo,
      'data_criacao': dataCriacao,
      'duracao_segundos': duracaoSegundos,
      'motivo_parada': motivoParada,
      'maior_pico': maiorPico,
    };
  }

  factory Gravacao.fromMap(Map<String, dynamic> map) {
    return Gravacao(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      nome: map['nome'] as String,
      caminhoArquivo: map['caminho_arquivo'] as String,
      dataCriacao: map['data_criacao'] as String,
      duracaoSegundos: (map['duracao_segundos'] as int?) ?? 0,
      motivoParada: map['motivo_parada'] as String?,
      maiorPico: (map['maior_pico'] as num?)?.toDouble() ?? -160.0,
    );
  }
}
