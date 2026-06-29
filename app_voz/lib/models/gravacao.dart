class GravacaoStatus {
  static const concluida = 'concluida';
  static const interrompida = 'interrompida';
  static const arquivoAusente = 'arquivo_ausente';
  static const excluida = 'excluida';

  static const ativos = {concluida, interrompida, arquivoAusente};
  static const todos = {...ativos, excluida};

  static bool isValid(String status) => todos.contains(status);
}

class Gravacao {
  final int? id;
  final int usuarioId;
  final int? projetoId;
  final String nome;
  final String caminhoArquivo;
  final String dataCriacao;
  final int duracaoSegundos;
  final String status;
  final int tamanhoBytes;
  final String formatoAudio;

  Gravacao({
    this.id,
    required this.usuarioId,
    this.projetoId,
    required this.nome,
    required this.caminhoArquivo,
    required this.dataCriacao,
    this.duracaoSegundos = 0,
    this.status = GravacaoStatus.concluida,
    this.tamanhoBytes = 0,
    this.formatoAudio = 'm4a',
  }) {
    if (!GravacaoStatus.isValid(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Status de gravacao invalido',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'projeto_id': projetoId,
      'nome': nome,
      'caminho_arquivo': caminhoArquivo,
      'data_criacao': dataCriacao,
      'duracao_segundos': duracaoSegundos,
      'status': status,
      'tamanho_bytes': tamanhoBytes,
      'formato_audio': formatoAudio,
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
      status: (map['status'] as String?) ?? GravacaoStatus.concluida,
      tamanhoBytes: (map['tamanho_bytes'] as int?) ?? 0,
      formatoAudio: (map['formato_audio'] as String?) ?? 'm4a',
    );
  }

  Gravacao copyWith({
    int? id,
    int? usuarioId,
    int? projetoId,
    bool clearProjetoId = false,
    String? nome,
    String? caminhoArquivo,
    String? dataCriacao,
    int? duracaoSegundos,
    String? status,
    int? tamanhoBytes,
    String? formatoAudio,
  }) {
    return Gravacao(
      id: id ?? this.id,
      usuarioId: usuarioId ?? this.usuarioId,
      projetoId: clearProjetoId ? null : projetoId ?? this.projetoId,
      nome: nome ?? this.nome,
      caminhoArquivo: caminhoArquivo ?? this.caminhoArquivo,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      duracaoSegundos: duracaoSegundos ?? this.duracaoSegundos,
      status: status ?? this.status,
      tamanhoBytes: tamanhoBytes ?? this.tamanhoBytes,
      formatoAudio: formatoAudio ?? this.formatoAudio,
    );
  }
}
