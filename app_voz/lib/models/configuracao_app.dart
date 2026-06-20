class ConfiguracaoApp {
  final int id;
  final bool comandosVozAtivos;
  final bool primeiraExecucaoConcluida;
  final bool escutaContinua;
  final bool feedbackSonoro;
  final bool paradaSilencio;
  final int tempoSilencioSegundos;
  final double limiarSilencioDb;
  final bool temaEscuro;
  final String dataAtualizacao;

  static const double limiarSilencioDbPadrao = -30.0;
  static const double limiarSilencioDbMin = -60.0;
  static const double limiarSilencioDbMax = -10.0;

  ConfiguracaoApp({
    this.id = 1,
    required this.comandosVozAtivos,
    required this.primeiraExecucaoConcluida,
    required this.escutaContinua,
    required this.feedbackSonoro,
    required this.paradaSilencio,
    required this.tempoSilencioSegundos,
    this.limiarSilencioDb = limiarSilencioDbPadrao,
    required this.temaEscuro,
    required this.dataAtualizacao,
  });

  factory ConfiguracaoApp.padrao() {
    return ConfiguracaoApp(
      comandosVozAtivos: true,
      primeiraExecucaoConcluida: false,
      escutaContinua: true,
      feedbackSonoro: false,
      paradaSilencio: true,
      tempoSilencioSegundos: 3,
      limiarSilencioDb: limiarSilencioDbPadrao,
      temaEscuro: true,
      dataAtualizacao: DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'comandos_voz_ativos': comandosVozAtivos ? 1 : 0,
      'primeira_execucao_concluida': primeiraExecucaoConcluida ? 1 : 0,
      'escuta_continua': escutaContinua ? 1 : 0,
      'feedback_sonoro': feedbackSonoro ? 1 : 0,
      'parada_silencio': paradaSilencio ? 1 : 0,
      'tempo_silencio_segundos': tempoSilencioSegundos,
      'limiar_silencio_db': limiarSilencioDb,
      'tema_escuro': temaEscuro ? 1 : 0,
      'data_atualizacao': dataAtualizacao,
    };
  }

  factory ConfiguracaoApp.fromMap(Map<String, dynamic> map) {
    return ConfiguracaoApp(
      id: map['id'] as int,
      comandosVozAtivos: (map['comandos_voz_ativos'] as int) == 1,
      primeiraExecucaoConcluida:
          (map['primeira_execucao_concluida'] as int) == 1,
      escutaContinua: (map['escuta_continua'] as int) == 1,
      feedbackSonoro: (map['feedback_sonoro'] as int) == 1,
      paradaSilencio: (map['parada_silencio'] as int) == 1,
      tempoSilencioSegundos: map['tempo_silencio_segundos'] as int,
      limiarSilencioDb: (map['limiar_silencio_db'] as num?)?.toDouble() ??
          limiarSilencioDbPadrao,
      temaEscuro: (map['tema_escuro'] as int? ?? 0) == 1,
      dataAtualizacao: map['data_atualizacao'] as String,
    );
  }

  ConfiguracaoApp copyWith({
    bool? comandosVozAtivos,
    bool? primeiraExecucaoConcluida,
    bool? escutaContinua,
    bool? feedbackSonoro,
    bool? paradaSilencio,
    int? tempoSilencioSegundos,
    double? limiarSilencioDb,
    bool? temaEscuro,
    String? dataAtualizacao,
  }) {
    return ConfiguracaoApp(
      id: id,
      comandosVozAtivos: comandosVozAtivos ?? this.comandosVozAtivos,
      primeiraExecucaoConcluida:
          primeiraExecucaoConcluida ?? this.primeiraExecucaoConcluida,
      escutaContinua: escutaContinua ?? this.escutaContinua,
      feedbackSonoro: feedbackSonoro ?? this.feedbackSonoro,
      paradaSilencio: paradaSilencio ?? this.paradaSilencio,
      tempoSilencioSegundos:
          tempoSilencioSegundos ?? this.tempoSilencioSegundos,
      limiarSilencioDb: limiarSilencioDb ?? this.limiarSilencioDb,
      temaEscuro: temaEscuro ?? this.temaEscuro,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }
}
