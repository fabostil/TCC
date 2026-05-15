enum VoiceCommandType {
  iniciarGravacao,
  pausarGravacao,
  retomarGravacao,
  encerrarGravacao,
  pararReproducao,
  reproduzirGravacao,
  listarGravacoes,
  criarMarcador,
  limparTexto,
  definirNomeProjeto,
  definirDescricaoProjeto,
  abrirProjetoPorNome,
  abrirNovoProjeto,
  abrirDashboard,
  abrirProjetos,
  abrirGravacoes,
  abrirConfiguracoes,
  abrirAssistente,
  abrirHistorico,
  abrirEditor,
  renomearGravacao,
  excluirGravacao,
  ativarControleVoz,
  desativarControleVoz,
  ativarEscutaContinua,
  desativarEscutaContinua,
  ativarFeedbackSonoro,
  desativarFeedbackSonoro,
  ativarParadaSilencio,
  desativarParadaSilencio,
  definirTempoSilencio,
  voltar,
  sair,
  desconhecido,
}

class CommandResult {
  const CommandResult({
    required this.originalText,
    required this.normalizedText,
    required this.type,
    required this.recognized,
    required this.tipoComando,
    this.acaoExecutada,
    this.parametro,
    this.parametroSecundario,
  });

  final String originalText;
  final String normalizedText;
  final VoiceCommandType type;
  final bool recognized;
  final String tipoComando;
  final String? acaoExecutada;
  final String? parametro;
  final String? parametroSecundario;

  String get statusReconhecimento =>
      recognized ? 'reconhecido' : 'nao_reconhecido';
}

class CommandService {
  const CommandService();

  CommandResult interpret(String text) {
    final normalizedText = normalize(text);

    if (normalizedText.isEmpty) {
      return _unknown(text, normalizedText);
    }

    if (_containsAny(normalizedText, const [
          'iniciar gravacao',
          'comecar gravacao',
        ]) ||
        _containsWord(normalizedText, 'gravar')) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.iniciarGravacao,
        tipoComando: 'iniciar_gravacao',
        acaoExecutada: 'Iniciar gravacao',
      );
    }

    if (_containsAny(normalizedText, const ['pausar gravacao']) ||
        normalizedText == 'pausar') {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.pausarGravacao,
        tipoComando: 'pausar_gravacao',
        acaoExecutada: 'Pausar gravacao',
      );
    }

    if (_containsAny(normalizedText, const [
      'retomar gravacao',
      'continuar gravacao',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.retomarGravacao,
        tipoComando: 'retomar_gravacao',
        acaoExecutada: 'Retomar gravacao',
      );
    }

    if (_containsAny(normalizedText, const [
      'encerrar gravacao',
      'parar gravacao',
      'finalizar gravacao',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.encerrarGravacao,
        tipoComando: 'encerrar_gravacao',
        acaoExecutada: 'Encerrar gravacao',
      );
    }

    if (_containsAny(normalizedText, const [
      'parar reproducao',
      'parar audio',
      'parar som',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.pararReproducao,
        tipoComando: 'parar_reproducao',
        acaoExecutada: 'Parar reproducao',
      );
    }

    if (!_looksLikeDescriptionCommand(normalizedText) &&
        (_containsAny(normalizedText, const ['reproduzir']) ||
            _containsWord(normalizedText, 'tocar'))) {
      final gravacao = _extractAfterAny(normalizedText, const [
        'reproduzir gravacao',
        'tocar gravacao',
        'reproduzir audio',
        'tocar audio',
      ]);

      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravacao',
        parametro: gravacao,
      );
    }

    if (_containsAny(normalizedText, const [
      'listar gravacoes',
      'mostrar gravacoes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.listarGravacoes,
        tipoComando: 'listar_gravacoes',
        acaoExecutada: 'Listar gravacoes',
      );
    }

    if (_containsAny(normalizedText, const ['criar marcador']) ||
        _containsWord(normalizedText, 'marcar')) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.criarMarcador,
        tipoComando: 'criar_marcador',
        acaoExecutada: 'Criar marcador',
      );
    }

    if (_containsWord(normalizedText, 'limpar')) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.limparTexto,
        tipoComando: 'limpar_texto',
        acaoExecutada: 'Limpar texto reconhecido',
      );
    }

    final nomeProjeto = _extractAfterAny(normalizedText, const [
      'eu quero que voce coloque o nome do projeto',
      'quero que voce coloque o nome do projeto',
      'coloque o nome do projeto',
      'colocar o nome do projeto',
      'defina o nome do projeto',
      'definir o nome do projeto',
      'nome do projeto',
      'nome projeto',
      'definir nome do projeto',
      'preencher nome do projeto',
      'coloque o nome',
      'colocar o nome',
      'defina o nome',
      'definir o nome',
      'quero que voce coloque o nome',
      'eu quero que voce coloque o nome',
      'chamar de',
      'salvar como',
    ]);
    if (nomeProjeto != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.definirNomeProjeto,
        tipoComando: 'definir_nome_projeto',
        acaoExecutada: 'Definir nome do projeto',
        parametro: _cleanShortName(nomeProjeto),
      );
    }

    final descricaoProjeto = _extractAfterAny(normalizedText, const [
      'eu quero que voce coloque a descricao do projeto',
      'quero que voce coloque a descricao do projeto',
      'coloque a descricao do projeto',
      'colocar a descricao do projeto',
      'defina a descricao do projeto',
      'definir a descricao do projeto',
      'descricao do projeto',
      'descricao projeto',
      'definir descricao do projeto',
      'preencher descricao do projeto',
      'coloque a descricao',
      'colocar a descricao',
      'defina a descricao',
      'definir a descricao',
      'descrever projeto',
      'descrição projeto',
    ]);
    if (descricaoProjeto != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.definirDescricaoProjeto,
        tipoComando: 'definir_descricao_projeto',
        acaoExecutada: 'Definir descricao do projeto',
        parametro: _polishSentence(descricaoProjeto),
      );
    }

    final projetoParaAbrir = _extractAfterAny(normalizedText, const [
      'abrir projeto',
      'entrar no projeto',
      'acessar projeto',
      'abre o projeto',
      'abrir o projeto',
      'entrar no',
      'acessar o',
    ]);
    if (projetoParaAbrir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirProjetoPorNome,
        tipoComando: 'abrir_projeto_por_nome',
        acaoExecutada: 'Abrir projeto por nome',
        parametro: projetoParaAbrir,
      );
    }

    if (_containsAny(normalizedText, const [
      'novo projeto',
      'criar projeto',
      'criar novo projeto',
      'abrir novo projeto',
      'adicionar projeto',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirNovoProjeto,
        tipoComando: 'abrir_novo_projeto',
        acaoExecutada: 'Abrir novo projeto',
      );
    }

    final renomearGravacao = _extractRenameRecording(normalizedText);
    if (renomearGravacao != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.renomearGravacao,
        tipoComando: 'renomear_gravacao',
        acaoExecutada: 'Renomear gravacao',
        parametro: renomearGravacao.$1,
        parametroSecundario: renomearGravacao.$2,
      );
    }

    final gravacaoParaExcluir = _extractAfterAny(normalizedText, const [
      'excluir gravacao',
      'apagar gravacao',
      'remover gravacao',
      'excluir audio',
      'apagar audio',
      'remover audio',
    ]);
    if (gravacaoParaExcluir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirGravacao,
        tipoComando: 'excluir_gravacao',
        acaoExecutada: 'Excluir gravacao',
        parametro: gravacaoParaExcluir,
      );
    }

    final gravacaoParaReproduzir = _extractAfterAny(normalizedText, const [
      'reproduzir gravacao',
      'tocar gravacao',
      'reproduzir audio',
      'tocar audio',
      'toque a gravacao',
      'toca a gravacao',
    ]);
    if (gravacaoParaReproduzir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravacao',
        parametro: gravacaoParaReproduzir,
      );
    }

    final tempoSilencio = _extractTempoSilencio(normalizedText);
    if (tempoSilencio != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.definirTempoSilencio,
        tipoComando: 'definir_tempo_silencio',
        acaoExecutada: 'Definir tempo de silencio',
        parametro: tempoSilencio.toString(),
      );
    }

    if (_containsAny(normalizedText, const [
      'ativar controle por voz',
      'ligar controle por voz',
      'ativar comandos de voz',
      'ligar comandos de voz',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.ativarControleVoz,
        tipoComando: 'ativar_controle_voz',
        acaoExecutada: 'Ativar controle por voz',
      );
    }

    if (_containsAny(normalizedText, const [
      'desativar controle por voz',
      'desligar controle por voz',
      'desativar comandos de voz',
      'desligar comandos de voz',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarControleVoz,
        tipoComando: 'desativar_controle_voz',
        acaoExecutada: 'Desativar controle por voz',
      );
    }

    if (_containsAny(normalizedText, const [
      'ativar escuta continua',
      'ligar escuta continua',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.ativarEscutaContinua,
        tipoComando: 'ativar_escuta_continua',
        acaoExecutada: 'Ativar escuta continua',
      );
    }

    if (_containsAny(normalizedText, const [
      'desativar escuta continua',
      'desligar escuta continua',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarEscutaContinua,
        tipoComando: 'desativar_escuta_continua',
        acaoExecutada: 'Desativar escuta continua',
      );
    }

    if (_containsAny(normalizedText, const [
      'ativar feedback sonoro',
      'ligar feedback sonoro',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.ativarFeedbackSonoro,
        tipoComando: 'ativar_feedback_sonoro',
        acaoExecutada: 'Ativar feedback sonoro',
      );
    }

    if (_containsAny(normalizedText, const [
      'desativar feedback sonoro',
      'desligar feedback sonoro',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarFeedbackSonoro,
        tipoComando: 'desativar_feedback_sonoro',
        acaoExecutada: 'Desativar feedback sonoro',
      );
    }

    if (_containsAny(normalizedText, const [
      'ativar parada por silencio',
      'ligar parada por silencio',
      'ativar parada automatica',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.ativarParadaSilencio,
        tipoComando: 'ativar_parada_silencio',
        acaoExecutada: 'Ativar parada por silencio',
      );
    }

    if (_containsAny(normalizedText, const [
      'desativar parada por silencio',
      'desligar parada por silencio',
      'desativar parada automatica',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarParadaSilencio,
        tipoComando: 'desativar_parada_silencio',
        acaoExecutada: 'Desativar parada por silencio',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir editor',
      'ir para editor',
      'editor musical',
      'abrir gravador',
      'ir para gravador',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirEditor,
        tipoComando: 'abrir_editor',
        acaoExecutada: 'Abrir editor',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir dashboard',
      'mostrar dashboard',
      'ir para dashboard',
      'meus numeros',
      'minhas metricas',
      'ver metricas',
      'minha produtividade',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDashboard,
        tipoComando: 'abrir_dashboard',
        acaoExecutada: 'Abrir dashboard',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir projetos',
      'mostrar projetos',
      'ir para projetos',
      'meus projetos',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirProjetos,
        tipoComando: 'abrir_projetos',
        acaoExecutada: 'Abrir projetos',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir gravacoes',
      'mostrar gravacoes',
      'minhas gravacoes',
      'ir para gravacoes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirGravacoes,
        tipoComando: 'abrir_gravacoes',
        acaoExecutada: 'Abrir gravacoes',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir configuracoes',
      'mostrar configuracoes',
      'ir para configuracoes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirConfiguracoes,
        tipoComando: 'abrir_configuracoes',
        acaoExecutada: 'Abrir configuracoes',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir assistente',
      'abrir assistente de voz',
      'ir para assistente',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirAssistente,
        tipoComando: 'abrir_assistente',
        acaoExecutada: 'Abrir assistente',
      );
    }

    if (_containsAny(normalizedText, const [
      'abrir historico',
      'mostrar historico',
      'ir para historico',
      'atividade recente',
      'minha atividade recente',
      'linha do tempo',
      'historico de atividades',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirHistorico,
        tipoComando: 'abrir_historico',
        acaoExecutada: 'Abrir historico',
      );
    }

    if (_containsAny(normalizedText, const ['voltar', 'voltar tela'])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.voltar,
        tipoComando: 'voltar',
        acaoExecutada: 'Voltar tela',
      );
    }

    if (_containsAny(normalizedText, const ['sair', 'fazer logout'])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.sair,
        tipoComando: 'sair',
        acaoExecutada: 'Sair',
      );
    }

    return _unknown(text, normalizedText);
  }

  String normalize(String text) {
    final lower = text.toLowerCase().trim();
    final withoutAccents = lower
        .replaceAll(RegExp('[\\u00e1\\u00e0\\u00e2\\u00e3\\u00e4]'), 'a')
        .replaceAll(RegExp('[\\u00e9\\u00e8\\u00ea\\u00eb]'), 'e')
        .replaceAll(RegExp('[\\u00ed\\u00ec\\u00ee\\u00ef]'), 'i')
        .replaceAll(RegExp('[\\u00f3\\u00f2\\u00f4\\u00f5\\u00f6]'), 'o')
        .replaceAll(RegExp('[\\u00fa\\u00f9\\u00fb\\u00fc]'), 'u')
        .replaceAll('\u00e7', 'c');

    return withoutAccents.replaceAll(RegExp(r'\s+'), ' ');
  }

  CommandResult _recognized(
    String originalText,
    String normalizedText,
    VoiceCommandType type, {
    required String tipoComando,
    required String acaoExecutada,
    String? parametro,
    String? parametroSecundario,
  }) {
    return CommandResult(
      originalText: originalText,
      normalizedText: normalizedText,
      type: type,
      recognized: true,
      tipoComando: tipoComando,
      acaoExecutada: acaoExecutada,
      parametro: parametro,
      parametroSecundario: parametroSecundario,
    );
  }

  CommandResult _unknown(String originalText, String normalizedText) {
    return CommandResult(
      originalText: originalText,
      normalizedText: normalizedText,
      type: VoiceCommandType.desconhecido,
      recognized: false,
      tipoComando: 'desconhecido',
    );
  }

  bool _containsAny(String text, List<String> patterns) {
    return patterns.any(text.contains);
  }

  bool _containsWord(String text, String word) {
    return RegExp('(^| )$word( |\$)').hasMatch(text);
  }

  bool _looksLikeDescriptionCommand(String text) {
    return _containsAny(text, const [
      'descricao do projeto',
      'descricao projeto',
      'coloque a descricao',
      'colocar a descricao',
      'defina a descricao',
      'definir a descricao',
    ]);
  }

  String? _extractAfterAny(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (text == prefix) {
        return null;
      }

      if (text.startsWith('$prefix ')) {
        final value = text.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }

    return null;
  }

  (String, String)? _extractRenameRecording(String text) {
    final match = RegExp(
      r'^(renomear|nomear) gravacao (.+) para (.+)$',
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    final atual = match.group(2)?.trim();
    final novo = match.group(3)?.trim();

    if (atual == null || atual.isEmpty || novo == null || novo.isEmpty) {
      return null;
    }

    return (atual, novo);
  }

  int? _extractTempoSilencio(String text) {
    final match = RegExp(
      r'^(definir |ajustar |alterar )?tempo de silencio (para )?(\d{1,2})( segundos?)?$',
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    final value = int.tryParse(match.group(3) ?? '');
    if (value == null) {
      return null;
    }

    return value.clamp(3, 12).toInt();
  }

  String _cleanShortName(String value) {
    return value.replaceFirst(RegExp(r'^(do|da|de|para|como) '), '').trim();
  }

  String _polishSentence(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      return cleaned;
    }

    final withoutTrailingDot = cleaned.replaceFirst(RegExp(r'[.!?]+$'), '');
    final first = withoutTrailingDot.substring(0, 1).toUpperCase();
    final rest = withoutTrailingDot.length == 1
        ? ''
        : withoutTrailingDot.substring(1);
    return '$first$rest.';
  }
}
