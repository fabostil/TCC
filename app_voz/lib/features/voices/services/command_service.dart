enum VoiceCommandType {
  iniciarGravacao,
  pausarGravacao,
  retomarGravacao,
  encerrarGravacao,
  pararReproducao,
  reproduzirGravacao,
  listarGravacoes,
  buscarGravacoes,
  buscarProjetos,
  limparBusca,
  criarMarcador,
  limparTexto,
  definirNomeProjeto,
  definirDescricaoProjeto,
  substituirNomeProjeto,
  substituirDescricaoProjeto,
  renomearProjeto,
  excluirProjeto,
  abrirProjetoPorNome,
  abrirNovoProjeto,
  criarProjeto,
  cancelarProjeto,
  abrirDashboard,
  abrirProjetos,
  abrirGravacoes,
  abrirDetalhesGravacao,
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
  ativarTemaEscuro,
  desativarTemaEscuro,
  ativarParadaSilencio,
  desativarParadaSilencio,
  definirTempoSilencio,
  confirmarAcao,
  cancelarAcao,
  scrollBaixo,
  scrollCima,
  scrollTopo,
  scrollFim,
  voltar,
  sair,
  comecarExperiencia,
  jaTenhoConta,
  permitirMicrofone,
  continuarFluxo,
  entrarConta,
  criarComandoPersonalizado,
  ativarComandoPersonalizado,
  desativarComandoPersonalizado,
  excluirComandoPersonalizado,
  desconhecido,
}

const unknownVoiceCommandMessage =
    'Não entendi o comando. Tente dizer: meus projetos, minhas gravações ou configurações.';

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

    final essentialCommand = _interpretEssentialCommand(text, normalizedText);
    if (essentialCommand != null) {
      return essentialCommand;
    }

    if (_containsAny(normalizedText, const [
          'iniciar gravacao',
          'comecar gravacao',
          'comecar a gravar',
          'comece a gravar',
          'comeca a gravar',
          'nova gravacao',
          'registrar audio',
          'capturar audio',
          'iniciar audio',
          'comecar recording',
        ]) ||
        (_containsWord(normalizedText, 'gravar') &&
            normalizedText != 'voltar a gravar')) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.iniciarGravacao,
        tipoComando: 'iniciar_gravacao',
        acaoExecutada: 'Iniciar gravação',
      );
    }

    if (_containsAny(normalizedText, const [
          'pausar gravacao',
          'pausa gravacao',
          'dar pausa',
          'segurar gravacao',
        ]) ||
        normalizedText == 'pausar' ||
        normalizedText == 'pausa') {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.pausarGravacao,
        tipoComando: 'pausar_gravacao',
        acaoExecutada: 'Pausar gravação',
      );
    }

    if (_containsAny(normalizedText, const [
          'retomar gravacao',
          'continuar gravacao',
          'continua gravacao',
          'voltar a gravar',
          'prosseguir gravacao',
        ]) ||
        normalizedText == 'retomar') {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.retomarGravacao,
        tipoComando: 'retomar_gravacao',
        acaoExecutada: 'Retomar gravação',
      );
    }

    if (_containsAny(normalizedText, const [
      'encerrar gravacao',
      'parar gravacao',
      'finalizar gravacao',
      'terminar gravacao',
      'salvar gravacao',
      'concluir gravacao',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.encerrarGravacao,
        tipoComando: 'encerrar_gravacao',
        acaoExecutada: 'Encerrar gravação',
      );
    }

    if (_containsAny(normalizedText, const [
      'parar reproducao',
      'parar audio',
      'parar som',
      'pausar reproducao',
      'interromper reproducao',
      'parar',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.pararReproducao,
        tipoComando: 'parar_reproducao',
        acaoExecutada: 'Parar reprodução',
      );
    }

    final ordinalGravacao = RegExp(
      r'^(primeira|segunda|terceira|quarta|quinta) gravacao$',
    ).firstMatch(normalizedText);
    if (ordinalGravacao != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravação',
        parametro: ordinalGravacao.group(1),
      );
    }

    if (!_looksLikeDescriptionCommand(normalizedText) &&
        (_containsAny(normalizedText, const [
              'reproduzir',
              'dar play',
              'ouvir',
              'escutar',
            ]) ||
            _containsWord(normalizedText, 'tocar') ||
            normalizedText == 'play')) {
      final gravacao = _extractAfterAny(normalizedText, const [
        'reproduzir gravacao',
        'tocar gravacao',
        'tocar a gravacao',
        'toca a gravacao',
        'reproduzir audio',
        'tocar audio',
        'dar play na gravacao',
        'dar play gravacao',
        'ouvir gravacao',
        'escutar gravacao',
        'ouvir audio',
        'escutar audio',
        'reproduzir a',
        'tocar a',
        'toque a',
        'toca a',
      ]);

      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravação',
        parametro: gravacao,
      );
    }

    if (_containsAny(normalizedText, const [
      'listar gravacoes',
      'mostrar gravacoes',
      'ver gravacoes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.listarGravacoes,
        tipoComando: 'listar_gravacoes',
        acaoExecutada: 'Listar gravacoes',
      );
    }

    final buscaGravacoes = _extractAfterAny(normalizedText, const [
      'buscar gravacoes por',
      'buscar gravacao por',
      'buscar gravacoes',
      'buscar gravacao',
      'procurar gravacoes por',
      'procurar gravacao por',
      'procurar gravacoes',
      'procurar gravacao',
      'filtrar gravacoes por',
      'filtrar gravacao por',
      'filtrar gravacoes',
      'filtrar gravacao',
    ]);
    if (buscaGravacoes != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.buscarGravacoes,
        tipoComando: 'buscar_gravacoes',
        acaoExecutada: 'Buscar gravacoes',
        parametro: _cleanShortName(buscaGravacoes),
      );
    }

    if (_containsAny(normalizedText, const [
      'limpar busca',
      'limpar filtro',
      'remover busca',
      'remover filtro',
      'mostrar tudo',
      'mostrar todos',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.limparBusca,
        tipoComando: 'limpar_busca',
        acaoExecutada: 'Limpar busca',
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

    final substituirNomeProjeto = _extractProjectReplacement(
      normalizedText,
      const ['nome', 'nome do projeto'],
    );
    if (substituirNomeProjeto != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.substituirNomeProjeto,
        tipoComando: 'substituir_nome_projeto',
        acaoExecutada: 'Substituir nome do projeto',
        parametro: _cleanShortName(substituirNomeProjeto),
      );
    }

    final substituirDescricaoProjeto = _extractProjectReplacement(
      normalizedText,
      const ['descricao', 'descricao do projeto'],
    );
    if (substituirDescricaoProjeto != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.substituirDescricaoProjeto,
        tipoComando: 'substituir_descricao_projeto',
        acaoExecutada: 'Substituir descricao do projeto',
        parametro: _polishSentence(substituirDescricaoProjeto),
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
    if (_matchesAny(normalizedText, const [
      'descricao',
      'editar descricao',
      'campo descricao',
      'descricao do projeto',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.definirDescricaoProjeto,
        tipoComando: 'definir_descricao_projeto',
        acaoExecutada: 'Definir descricao do projeto',
      );
    }

    final renomearProjeto = _extractRenameProject(normalizedText);
    if (renomearProjeto != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.renomearProjeto,
        tipoComando: 'renomear_projeto',
        acaoExecutada: 'Renomear projeto',
        parametro: renomearProjeto.$1,
        parametroSecundario: renomearProjeto.$2,
      );
    }
    if (const [
      'renomear projeto',
      'editar projeto',
      'alterar projeto',
      'mudar nome do projeto',
    ].contains(normalizedText)) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.renomearProjeto,
        tipoComando: 'renomear_projeto',
        acaoExecutada: 'Renomear projeto',
      );
    }

    final projetoParaExcluir = _extractAfterAny(normalizedText, const [
      'excluir projeto',
      'apagar projeto',
      'remover projeto',
      'deletar projeto',
    ]);
    if (projetoParaExcluir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirProjeto,
        tipoComando: 'excluir_projeto',
        acaoExecutada: 'Excluir projeto',
        parametro: _cleanShortName(projetoParaExcluir),
      );
    }
    if (const [
      'excluir projeto',
      'apagar projeto',
      'remover projeto',
      'deletar projeto',
    ].contains(normalizedText)) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirProjeto,
        tipoComando: 'excluir_projeto',
        acaoExecutada: 'Excluir projeto',
      );
    }

    final projetoParaAbrir = _extractAfterAny(normalizedText, const [
      'abrir projeto',
      'abre projeto',
      'ver projeto',
      'mostrar projeto',
      'entrar no projeto',
      'abrir meu projeto',
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
    if (const [
      'abrir projeto',
      'abre projeto',
      'ver projeto',
      'mostrar projeto',
      'entrar no projeto',
      'abrir meu projeto',
    ].contains(normalizedText)) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirProjetoPorNome,
        tipoComando: 'abrir_projeto_por_nome',
        acaoExecutada: 'Abrir projeto por nome',
      );
    }

    final buscaProjetos = _extractAfterAny(normalizedText, const [
      'buscar projetos por',
      'buscar projeto por',
      'buscar projetos',
      'buscar projeto',
      'procurar projetos por',
      'procurar projeto por',
      'procurar projetos',
      'procurar projeto',
      'filtrar projetos por',
      'filtrar projeto por',
      'filtrar projetos',
      'filtrar projeto',
    ]);
    if (buscaProjetos != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.buscarProjetos,
        tipoComando: 'buscar_projetos',
        acaoExecutada: 'Buscar projetos',
        parametro: _cleanShortName(buscaProjetos),
      );
    }

    if (_containsAny(normalizedText, const [
      'criar projeto',
      'salvar projeto',
      'confirmar projeto',
      'finalizar projeto',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.criarProjeto,
        tipoComando: 'criar_projeto',
        acaoExecutada: 'Criar projeto',
      );
    }

    if (_containsAny(normalizedText, const [
      'cancelar projeto',
      'cancelar criacao',
      'cancelar novo projeto',
      'fechar novo projeto',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.cancelarProjeto,
        tipoComando: 'cancelar_projeto',
        acaoExecutada: 'Cancelar projeto',
      );
    }

    if (_containsAny(normalizedText, const [
      'novo projeto',
      'criar novo projeto',
      'abrir novo projeto',
      'adicionar projeto',
      'adiciona projeto',
      'novo trabalho',
      'novo som',
      'nova musica',
      'comecar projeto',
      'cria projeto',
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
        acaoExecutada: 'Renomear gravação',
        parametro: renomearGravacao.$1,
        parametroSecundario: renomearGravacao.$2,
      );
    }

    final detalhesGravacao = _extractAfterAny(normalizedText, const [
      'abrir detalhes da gravacao',
      'abrir detalhes gravacao',
      'abrir detalhes',
      'ver detalhes',
      'detalhes',
      'ver detalhes da gravacao',
      'ver detalhes gravacao',
      'mostrar detalhes da gravacao',
      'mostrar detalhes gravacao',
      'informacoes da gravacao',
      'informacoes gravacao',
      'detalhes da gravacao',
      'detalhes gravacao',
    ]);
    if (detalhesGravacao != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes da gravação',
        parametro: detalhesGravacao,
      );
    }
    if (_containsAny(normalizedText, const [
      'abrir detalhes da gravacao',
      'abrir detalhes gravacao',
      'abrir detalhes',
      'ver detalhes',
      'detalhes',
      'ver detalhes da gravacao',
      'ver detalhes gravacao',
      'mostrar detalhes da gravacao',
      'mostrar detalhes gravacao',
      'informacoes da gravacao',
      'informacoes gravacao',
      'detalhes da gravacao',
      'detalhes gravacao',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes da gravação',
      );
    }

    final gravacaoParaExcluir = _extractAfterAny(normalizedText, const [
      'excluir gravacao',
      'apagar gravacao',
      'remover gravacao',
      'deletar gravacao',
      'excluir audio',
      'apagar audio',
      'remover audio',
      'deletar audio',
    ]);
    if (gravacaoParaExcluir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirGravacao,
        tipoComando: 'excluir_gravacao',
        acaoExecutada: 'Excluir gravação',
        parametro: gravacaoParaExcluir,
      );
    }
    if (const [
      'excluir gravacao',
      'apagar gravacao',
      'remover gravacao',
      'deletar gravacao',
    ].contains(normalizedText)) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirGravacao,
        tipoComando: 'excluir_gravacao',
        acaoExecutada: 'Excluir gravação',
      );
    }

    final gravacaoParaReproduzir = _extractAfterAny(normalizedText, const [
      'reproduzir gravacao',
      'tocar gravacao',
      'reproduzir audio',
      'tocar audio',
      'ouvir gravacao',
      'escutar gravacao',
      'ouvir audio',
      'escutar audio',
      'toque a gravacao',
      'toca a gravacao',
      'dar play na gravacao',
      'dar play gravacao',
      'reproduzir a',
      'tocar a',
      'toque a',
      'toca a',
    ]);
    if (gravacaoParaReproduzir != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravação',
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
        acaoExecutada: 'Definir tempo de silêncio',
        parametro: tempoSilencio.toString(),
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
      'desativar escuta continua',
      'desligar escuta continua',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarEscutaContinua,
        tipoComando: 'desativar_escuta_continua',
        acaoExecutada: 'Desativar escuta contínua',
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
        acaoExecutada: 'Ativar escuta contínua',
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
      'ativar tema claro',
      'usar tema claro',
      'modo claro',
      'tema claro',
      'desativar tema escuro',
      'desligar tema escuro',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarTemaEscuro,
        tipoComando: 'desativar_tema_escuro',
        acaoExecutada: 'Ativar tema claro',
      );
    }

    if (_containsAny(normalizedText, const [
      'ativar tema escuro',
      'ligar tema escuro',
      'usar tema escuro',
      'modo escuro',
      'tema escuro',
      'desativar tema claro',
      'desligar tema claro',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.ativarTemaEscuro,
        tipoComando: 'ativar_tema_escuro',
        acaoExecutada: 'Ativar tema escuro',
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
      'desativar parada por silencio',
      'desligar parada por silencio',
      'desativar parada automatica',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.desativarParadaSilencio,
        tipoComando: 'desativar_parada_silencio',
        acaoExecutada: 'Desativar parada por silêncio',
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
        acaoExecutada: 'Ativar parada por silêncio',
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

    if (_matchesAny(normalizedText, const [
      'dashboard',
      'abrir dashboard',
      'abre dashboard',
      'mostrar dashboard',
      'ver dashboard',
      'ir para dashboard',
      'vai para dashboard',
      'painel',
      'meu painel',
      'indicadores',
      'ver indicadores',
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

    if (_matchesAny(normalizedText, const [
      'projetos',
      'meus projetos',
      'abrir projetos',
      'abre projetos',
      'mostrar projetos',
      'ver projetos',
      'ir para projetos',
      'vai para projetos',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirProjetos,
        tipoComando: 'abrir_projetos',
        acaoExecutada: 'Abrir projetos',
      );
    }

    if (_matchesAny(normalizedText, const [
      'gravacoes',
      'minhas gravacoes',
      'abrir gravacoes',
      'abrir minhas gravacoes',
      'abre gravacoes',
      'mostrar gravacoes',
      'ver gravacoes',
      'ir para gravacoes',
      'vai para gravacoes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirGravacoes,
        tipoComando: 'abrir_gravacoes',
        acaoExecutada: 'Abrir gravacoes',
      );
    }

    if (_matchesAny(normalizedText, const [
      'configuracoes',
      'abrir configuracoes',
      'abre configuracoes',
      'mostrar configuracoes',
      'ver configuracoes',
      'ir para configuracoes',
      'vai para configuracoes',
      'ajustes',
      'preferencias',
      'minha conta',
      'conta',
      'abrir conta',
      'perfil',
      'configuracoes da conta',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirConfiguracoes,
        tipoComando: 'abrir_configuracoes',
        acaoExecutada: 'Abrir configurações',
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

    if (_matchesAny(normalizedText, const [
      'historico',
      'abrir historico',
      'abre historico',
      'mostrar historico',
      'ver historico',
      'ir para historico',
      'vai para historico',
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
        acaoExecutada: 'Abrir histórico',
      );
    }

    if (_isConfirmationCommand(normalizedText)) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.confirmarAcao,
        tipoComando: 'confirmar_acao',
        acaoExecutada: 'Confirmar ação',
      );
    }

    if (_containsAny(normalizedText, const [
      'cancelar exclusao',
      'cancelar acao',
      'cancelar',
      'desistir',
      'cancela',
      'nao excluir',
      'nao',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.cancelarAcao,
        tipoComando: 'cancelar_acao',
        acaoExecutada: 'Cancelar ação',
      );
    }

    if (_matchesAny(normalizedText, const [
      'rolar para baixo',
      'descer',
      'desce',
      'mais para baixo',
      'baixo',
      'proximos',
      'ver mais',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.scrollBaixo,
        tipoComando: 'scroll_baixo',
        acaoExecutada: 'Rolar para baixo',
      );
    }

    if (_matchesAny(normalizedText, const [
      'rolar para cima',
      'subir',
      'sobe',
      'mais para cima',
      'cima',
      'anteriores',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.scrollCima,
        tipoComando: 'scroll_cima',
        acaoExecutada: 'Rolar para cima',
      );
    }

    if (_matchesAny(normalizedText, const [
      'ir para o topo',
      'voltar para o topo',
      'topo',
      'comeco da lista',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.scrollTopo,
        tipoComando: 'scroll_topo',
        acaoExecutada: 'Ir para o topo',
      );
    }

    if (_matchesAny(normalizedText, const [
      'ir para o fim',
      'fim da lista',
      'final da lista',
      'fim da pagina',
      'ultimos',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.scrollFim,
        tipoComando: 'scroll_fim',
        acaoExecutada: 'Ir para o fim',
      );
    }

    if (_matchesAny(normalizedText, const [
      'voltar',
      'volta',
      'retornar',
      'retorna',
      'voltar tela',
      'voltar uma tela',
      'voltar para home',
      'ir para home',
      'home',
      'abre tela inicial',
      'abre a tela inicial',
      'abrir tela inicial',
      'tela inicial',
      'inicio',
      'ir para inicio',
      'ir para o inicio',
      'voltar para inicio',
      'voltar para o inicio',
      'voltar para tela inicial',
      'ir para tela inicial',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.voltar,
        tipoComando: 'voltar',
        acaoExecutada: 'Voltar tela',
      );
    }

    if (_containsAny(normalizedText, const ['sair', 'fazer logout', 'deslogar'])) {
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

  CommandResult? _interpretEssentialCommand(
    String originalText,
    String normalizedText,
  ) {
    final entryCommand = switch (normalizedText) {
      'comecar' => (
        VoiceCommandType.comecarExperiencia,
        'comecar_experiencia',
        'Comecar experiencia',
      ),
      'ja tenho conta' => (
        VoiceCommandType.jaTenhoConta,
        'ja_tenho_conta',
        'Ja tenho conta',
      ),
      'permitir microfone' => (
        VoiceCommandType.permitirMicrofone,
        'permitir_microfone',
        'Permitir microfone',
      ),
      'continuar' => (
        VoiceCommandType.continuarFluxo,
        'continuar_fluxo',
        'Continuar',
      ),
      'entrar' => (VoiceCommandType.entrarConta, 'entrar_conta', 'Entrar'),
      _ => null,
    };
    if (entryCommand != null) {
      return _recognized(
        originalText,
        normalizedText,
        entryCommand.$1,
        tipoComando: entryCommand.$2,
        acaoExecutada: entryCommand.$3,
      );
    }

    if (_equalsAny(normalizedText, const ['iniciar', 'vamos comecar'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.comecarExperiencia,
        tipoComando: 'comecar_experiencia',
        acaoExecutada: 'Comecar experiencia',
      );
    }

    if (_equalsAny(normalizedText, const ['tenho conta'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.jaTenhoConta,
        tipoComando: 'ja_tenho_conta',
        acaoExecutada: 'Ja tenho conta',
      );
    }

    if (_equalsAny(normalizedText, const ['fazer login', 'login'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.entrarConta,
        tipoComando: 'entrar_conta',
        acaoExecutada: 'Entrar',
      );
    }

    if (_equalsAny(normalizedText, const [
      'liberar microfone',
      'ativar microfone',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.permitirMicrofone,
        tipoComando: 'permitir_microfone',
        acaoExecutada: 'Permitir microfone',
      );
    }

    if (_equalsAny(normalizedText, const [
      'meus projetos',
      'abrir meus projetos',
      'abre meus projetos',
      'entrar em meus projetos',
      'vai para projetos',
      'projetos',
      'entrar em projetos',
      'lista de projetos',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirProjetos,
        tipoComando: 'abrir_projetos',
        acaoExecutada: 'Abrir projetos',
      );
    }

    if (_equalsAny(normalizedText, const [
      'minhas gravacoes',
      'abrir minhas gravacoes',
      'gravacoes',
      'lista de gravacoes',
      'audios',
      'meus audios',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirGravacoes,
        tipoComando: 'abrir_gravacoes',
        acaoExecutada: 'Abrir gravacoes',
      );
    }

    if (_equalsAny(normalizedText, const [
      'dashboard',
      'painel',
      'meu painel',
      'indicadores',
      'abrir painel',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirDashboard,
        tipoComando: 'abrir_dashboard',
        acaoExecutada: 'Abrir dashboard',
      );
    }

    if (_equalsAny(normalizedText, const [
      'historico',
      'acoes recentes',
      'registro',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirHistorico,
        tipoComando: 'abrir_historico',
        acaoExecutada: 'Abrir historico',
      );
    }

    if (_equalsAny(normalizedText, const [
      'configuracoes',
      'preferencias',
      'opcoes',
      'abrir opcoes',
      'abrir preferencias',
      'entrar em configuracoes',
      'minha conta',
      'conta',
      'abrir conta',
      'perfil',
      'configuracoes da conta',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirConfiguracoes,
        tipoComando: 'abrir_configuracoes',
        acaoExecutada: 'Abrir configuracoes',
      );
    }

    if (_equalsAny(normalizedText, const [
      'ajuda',
      'me ajuda',
      'preciso de ajuda',
      'comandos',
      'comandos disponiveis',
      'o que posso falar',
      'o que posso dizer',
      'ver ajuda',
      'mostrar ajuda',
      'abrir ajuda',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirAssistente,
        tipoComando: 'abrir_assistente',
        acaoExecutada: 'Mostrar ajuda',
      );
    }

    if (_equalsAny(normalizedText, const [
      'criar comando personalizado',
      'comando personalizado',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.criarComandoPersonalizado,
        tipoComando: 'criar_comando_personalizado',
        acaoExecutada: 'Criar comando personalizado',
      );
    }

    if (_equalsAny(normalizedText, const ['ativar comando'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.ativarComandoPersonalizado,
        tipoComando: 'ativar_comando_personalizado',
        acaoExecutada: 'Ativar comando personalizado',
      );
    }

    if (_equalsAny(normalizedText, const ['desativar comando'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.desativarComandoPersonalizado,
        tipoComando: 'desativar_comando_personalizado',
        acaoExecutada: 'Desativar comando personalizado',
      );
    }

    if (_equalsAny(normalizedText, const ['excluir comando'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.excluirComandoPersonalizado,
        tipoComando: 'excluir_comando_personalizado',
        acaoExecutada: 'Excluir comando personalizado',
      );
    }

    if (_equalsAny(normalizedText, const [
      'home',
      'inicio',
      'tela inicial',
      'voltar para tela inicial',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.voltar,
        tipoComando: 'voltar',
        acaoExecutada: 'Voltar tela',
      );
    }

    if (_equalsAny(normalizedText, const ['voltar'])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.voltar,
        tipoComando: 'voltar',
        acaoExecutada: 'Voltar tela',
      );
    }

    if (_equalsAny(normalizedText, const [
      'editor',
      'abrir editor',
      'abre editor',
      'ir para o editor',
      'entrar no editor',
      'area de gravacao',
      'tela de gravacao',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirEditor,
        tipoComando: 'abrir_editor',
        acaoExecutada: 'Abrir editor',
      );
    }

    if (_equalsAny(normalizedText, const [
      'novo projeto',
      'criar projeto',
      'abrir novo projeto',
      'adicionar projeto',
      'cadastrar projeto',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        normalizedText == 'criar projeto'
            ? VoiceCommandType.criarProjeto
            : VoiceCommandType.abrirNovoProjeto,
        tipoComando: normalizedText == 'criar projeto'
            ? 'criar_projeto'
            : 'abrir_novo_projeto',
        acaoExecutada: normalizedText == 'criar projeto'
            ? 'Criar projeto'
            : 'Abrir novo projeto',
      );
    }

    final novoProjetoComNome = _extractAfterAny(normalizedText, const [
      'criar projeto',
      'novo projeto',
      'abrir novo projeto',
    ]);
    if (novoProjetoComNome != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirNovoProjeto,
        tipoComando: 'abrir_novo_projeto',
        acaoExecutada: 'Abrir novo projeto',
        parametro: _cleanShortName(novoProjetoComNome),
      );
    }

    if (_equalsAny(normalizedText, const [
      'abrir projeto',
      'excluir projeto',
    ])) {
      return null;
    }

    if (_equalsAny(normalizedText, const [
      'descricao do projeto',
      'descricao',
      'editar descricao',
      'campo descricao',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.definirDescricaoProjeto,
        tipoComando: 'definir_descricao_projeto',
        acaoExecutada: 'Definir descricao do projeto',
      );
    }

    final descricaoDireta = normalizedText.startsWith('descricao do projeto ')
        ? null
        : _extractAfterAny(normalizedText, const ['descricao']);
    if (descricaoDireta != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.definirDescricaoProjeto,
        tipoComando: 'definir_descricao_projeto',
        acaoExecutada: 'Definir descricao do projeto',
        parametro: _polishSentence(descricaoDireta),
      );
    }

    final nomeGravacao = _extractAfterAny(normalizedText, const [
      'nome da gravacao',
    ]);
    if (nomeGravacao != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.renomearGravacao,
        tipoComando: 'renomear_gravacao',
        acaoExecutada: 'Renomear gravacao',
        parametroSecundario: _cleanShortName(nomeGravacao),
      );
    }

    if (_equalsAny(normalizedText, const [
      'editar nome da gravacao',
      'renomear gravacao',
      'mudar nome da gravacao',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.renomearGravacao,
        tipoComando: 'renomear_gravacao',
        acaoExecutada: 'Renomear gravacao',
      );
    }

    final detalhesDoItem = RegExp(
      r'^(abrir )?detalhes (do |da )?item ([0-9]+)$',
    ).firstMatch(normalizedText);
    if (detalhesDoItem != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes da gravacao',
        parametro: 'item ${detalhesDoItem.group(3)}',
      );
    }

    final excluirItem = RegExp(
      r'^(excluir|apagar|remover) item ([0-9]+)$',
    ).firstMatch(normalizedText);
    if (excluirItem != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.excluirGravacao,
        tipoComando: 'excluir_gravacao',
        acaoExecutada: 'Excluir gravacao',
        parametro: 'item ${excluirItem.group(2)}',
      );
    }

    if (_equalsAny(normalizedText, const [
      'descer',
      'subir',
      'ir para o fim',
      'ir para o topo',
    ])) {
      final type = switch (normalizedText) {
        'descer' => VoiceCommandType.scrollBaixo,
        'subir' => VoiceCommandType.scrollCima,
        'ir para o fim' => VoiceCommandType.scrollFim,
        _ => VoiceCommandType.scrollTopo,
      };
      final tipoComando = switch (type) {
        VoiceCommandType.scrollBaixo => 'scroll_baixo',
        VoiceCommandType.scrollCima => 'scroll_cima',
        VoiceCommandType.scrollFim => 'scroll_fim',
        _ => 'scroll_topo',
      };
      final acaoExecutada = switch (type) {
        VoiceCommandType.scrollBaixo => 'Rolar para baixo',
        VoiceCommandType.scrollCima => 'Rolar para cima',
        VoiceCommandType.scrollFim => 'Ir para o fim',
        _ => 'Ir para o topo',
      };
      return _recognized(
        originalText,
        normalizedText,
        type,
        tipoComando: tipoComando,
        acaoExecutada: acaoExecutada,
      );
    }

    if (_equalsAny(normalizedText, const [
      'confirmar',
      'sim',
      'confirmar acao',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.confirmarAcao,
        tipoComando: 'confirmar_acao',
        acaoExecutada: 'Confirmar acao',
      );
    }

    if (_equalsAny(normalizedText, const [
      'cancelar',
      'nao',
      'pode cancelar',
      'deixa pra la',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.cancelarAcao,
        tipoComando: 'cancelar_acao',
        acaoExecutada: 'Cancelar acao',
      );
    }

    return null;
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

    final withoutPunctuation = withoutAccents.replaceAll(
      RegExp(r'[^a-z0-9\s]'),
      ' ',
    );

    return withoutPunctuation.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  bool _matchesAny(String text, List<String> patterns) {
    return patterns.any((pattern) => text == pattern || text.contains(pattern));
  }

  bool _equalsAny(String text, List<String> patterns) {
    return patterns.contains(text);
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

  bool _isConfirmationCommand(String text) {
    return text == 'confirmar' ||
        text == 'confirmar exclusao' ||
        text == 'pode confirmar' ||
        text == 'confirmo' ||
        text == 'sim';
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

  (String, String)? _extractRenameProject(String text) {
    final match = RegExp(
      r'^(renomear|nomear|editar|alterar) projeto (.+) para (.+)$',
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

  String? _extractProjectReplacement(String text, List<String> fields) {
    for (final field in fields) {
      final patterns = [
        RegExp('^apague o $field .+ e coloque (.+)\$'),
        RegExp('^apague a $field .+ e coloque (.+)\$'),
        RegExp('^apague o $field e coloque (.+)\$'),
        RegExp('^apague a $field e coloque (.+)\$'),
        RegExp('^apagar o $field .+ e colocar (.+)\$'),
        RegExp('^apagar a $field .+ e colocar (.+)\$'),
        RegExp('^apagar o $field e colocar (.+)\$'),
        RegExp('^apagar a $field e colocar (.+)\$'),
        RegExp('^substituir o $field por (.+)\$'),
        RegExp('^substituir a $field por (.+)\$'),
        RegExp('^trocar o $field para (.+)\$'),
        RegExp('^trocar a $field para (.+)\$'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        final value = match?.group(1)?.trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    }

    return null;
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
