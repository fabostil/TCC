import 'package:flutter/foundation.dart';

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
  preencherFraseComando,
  salvarComandoPersonalizado,
  consultarTempoSilencio,
  ajustarTempoSilencio,
  consultarSensibilidadeSilencio,
  ajustarSensibilidadeSilencio,
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
      // Low-priority bare "nome X" — reached only if _interpretEssentialCommand
      // did not capture it (e.g. after adding project-passthrough exclusion).
      'nome',
    ]);
    if (nomeProjeto != null) {
      debugPrint(
        '[VoiceParser] raw=$text '
        'matched_rule=definirNomeProjeto_extract '
        'priority=normal context=project type=definirNomeProjeto',
      );
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

    if (_startsWithAny(normalizedText, const [
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

    // "detalhes do item N" → visual position lookup (parametro = "item N")
    final detalhesItemRef = _extractAfterAny(normalizedText, const [
      'abrir detalhes do item',
      'ver detalhes do item',
      'mostrar detalhes do item',
      'detalhes do item',
    ]);
    if (detalhesItemRef != null) {
      debugPrint(
        '[VoiceParser] raw=$text matched_rule=detalhes_item '
        'priority=normal context=recordings referenceType=item '
        'requestedTarget=$detalhesItemRef',
      );
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes por posição',
        parametro: 'item $detalhesItemRef',
      );
    }

    // "detalhes da gravacao N" → title lookup (parametro = "gravacao N" for numbers)
    final detalhesGravacaoRef = _extractAfterAny(normalizedText, const [
      'abrir detalhes da gravacao',
      'abrir detalhes gravacao',
      'ver detalhes da gravacao',
      'ver detalhes gravacao',
      'mostrar detalhes da gravacao',
      'mostrar detalhes gravacao',
      'informacoes da gravacao',
      'informacoes gravacao',
      'descricao da gravacao',
      'detalhes da gravacao',
      'detalhes gravacao',
    ]);
    if (detalhesGravacaoRef != null) {
      final param = _gravacaoRefParam(detalhesGravacaoRef);
      debugPrint(
        '[VoiceParser] raw=$text matched_rule=detalhes_gravacao '
        'priority=normal context=recordings referenceType=gravacaoTitle '
        'requestedTarget=$detalhesGravacaoRef',
      );
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes por título',
        parametro: param,
      );
    }

    // "detalhes de [nome]" → name lookup
    final detalhesDeNome = _extractAfterAny(normalizedText, const [
      'abrir detalhes de',
      'ver detalhes de',
      'detalhes de',
    ]);
    if (detalhesDeNome != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes por nome',
        parametro: detalhesDeNome,
      );
    }

    // Generic "abrir detalhes [algo]" / "ver detalhes [algo]" / "detalhes [algo]"
    final detalhesGenerico = _extractAfterAny(normalizedText, const [
      'abrir detalhes',
      'ver detalhes',
      'detalhes',
    ]);
    if (detalhesGenerico != null) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes',
        parametro: detalhesGenerico,
      );
    }
    if (_containsAny(normalizedText, const [
      'abrir detalhes',
      'ver detalhes',
      'informacoes',
      'detalhes',
    ])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.abrirDetalhesGravacao,
        tipoComando: 'abrir_detalhes_gravacao',
        acaoExecutada: 'Abrir detalhes',
      );
    }

    // "excluir gravacao N" / "apagar gravacao N" → title lookup for numbers
    final gravacaoParaExcluirRaw = _extractAfterAny(normalizedText, const [
      'excluir gravacao',
      'apagar gravacao',
      'remover gravacao',
      'deletar gravacao',
      'excluir audio',
      'apagar audio',
      'remover audio',
      'deletar audio',
    ]);
    if (gravacaoParaExcluirRaw != null) {
      final param = _gravacaoRefParam(gravacaoParaExcluirRaw);
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.excluirGravacao,
        tipoComando: 'excluir_gravacao',
        acaoExecutada: 'Excluir gravação',
        parametro: param,
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
      'desabilitar parada por silencio',
      'desabilitar parada automatica',
      'desabilitar parada automatica por silencio',
      'desativar parada automatica por silencio',
      'desligar parada automatica',
      'desligar parada automatica por silencio',
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
      'habilitar parada por silencio',
      'habilitar parada automatica',
      'habilitar parada automatica por silencio',
      'ativar parada automatica por silencio',
      'ligar parada automatica',
      'ligar parada automatica por silencio',
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
      'fechar',
      'fecha',
      'fechar tela',
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

    if (_equalsAny(normalizedText, const [
      'sair',
      'sair da conta',
      'fazer logout',
      'deslogar',
      'encerrar sessao',
      'encerrar conta',
    ])) {
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
          'adicionar comando personalizado',
          'novo comando personalizado',
          'cadastrar comando personalizado',
          'novo comando',
          'adicionar comando',
        ]) ||
        (_containsAny(normalizedText, const [
              'criar comando',
              'adicionar comando',
              'novo comando',
              'cadastrar comando',
            ]) &&
            normalizedText.contains(' para '))) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.criarComandoPersonalizado,
        tipoComando: 'criar_comando_personalizado',
        acaoExecutada: 'Criar comando personalizado',
      );
    }

    // "ativar/reativar/ligar comando [frase]" — with target
    for (final prefix in const [
      'ativar o comando ',
      'ativar comando ',
      'reativar o comando ',
      'reativar comando ',
      'ligar o comando ',
      'ligar comando ',
    ]) {
      if (normalizedText.startsWith(prefix)) {
        final frase = normalizedText.replaceFirst(prefix, '').trim();
        if (frase.isNotEmpty) {
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.ativarComandoPersonalizado,
            tipoComando: 'ativar_comando_personalizado',
            acaoExecutada: 'Ativar comando personalizado',
            parametro: frase,
          );
        }
      }
    }

    // "desativar/pausar/desligar comando [frase]" — with target
    for (final prefix in const [
      'desativar o comando ',
      'desativar comando ',
      'pausar o comando ',
      'pausar comando ',
      'desligar o comando ',
      'desligar comando ',
    ]) {
      if (normalizedText.startsWith(prefix)) {
        final frase = normalizedText.replaceFirst(prefix, '').trim();
        if (frase.isNotEmpty) {
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.desativarComandoPersonalizado,
            tipoComando: 'desativar_comando_personalizado',
            acaoExecutada: 'Desativar comando personalizado',
            parametro: frase,
          );
        }
      }
    }

    // "excluir/apagar/remover comando [frase]" — with target
    for (final prefix in const [
      'excluir o comando ',
      'excluir comando ',
      'apagar o comando ',
      'apagar comando ',
      'remover o comando ',
      'remover comando ',
    ]) {
      if (normalizedText.startsWith(prefix)) {
        final frase = normalizedText.replaceFirst(prefix, '').trim();
        if (frase.isNotEmpty) {
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.excluirComandoPersonalizado,
            tipoComando: 'excluir_comando_personalizado',
            acaoExecutada: 'Excluir comando personalizado',
            parametro: frase,
          );
        }
      }
    }

    // Bare ativar/desativar/excluir (no target)
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

    // "criar comando personalizado [frase]" — shortcut without "para"
    if (normalizedText.startsWith('criar comando personalizado ') &&
        !normalizedText.contains(' para ')) {
      final frase =
          normalizedText.replaceFirst('criar comando personalizado ', '').trim();
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.criarComandoPersonalizado,
        tipoComando: 'criar_comando_personalizado',
        acaoExecutada: 'Criar comando personalizado',
        parametro: frase.isNotEmpty ? frase : null,
      );
    }

    // Project-name commands — HIGH PRIORITY, must beat "nome [texto]" below.
    // "nome do projeto X", "nome projeto X", "colocar nome do projeto X",
    // "definir nome do projeto X" — all route to definirNomeProjeto.
    for (final prefix in const [
      'nome do projeto ',
      'nome projeto ',
      'colocar nome do projeto ',
      'colocar o nome do projeto ',
      'definir nome do projeto ',
      'definir o nome do projeto ',
    ]) {
      if (normalizedText.startsWith(prefix)) {
        final value = normalizedText.substring(prefix.length).trim();
        if (value.isNotEmpty) {
          debugPrint(
            '[VoiceParser] raw=$originalText '
            'matched_rule=definirNomeProjeto_prefix '
            'priority=high context=project type=definirNomeProjeto',
          );
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.definirNomeProjeto,
            tipoComando: 'definir_nome_projeto',
            acaoExecutada: 'Definir nome do projeto',
            parametro: _cleanShortName(value),
          );
        }
      }
    }

    // Recordings: "renomear gravacao N" / "renomear item N" without "para" —
    // opens the rename modal for the specified recording immediately.
    // Patterns with " para " fall through to _extractRenameRecording in the
    // main interpret() body.
    for (final entry in const [
      ('renomear gravacao ', 'gravacao'),
      ('renomear item ', 'item'),
      ('mudar nome da gravacao ', 'gravacao'),
      ('alterar nome da gravacao ', 'gravacao'),
      ('trocar nome da gravacao ', 'gravacao'),
      ('mudar nome do item ', 'item'),
      ('alterar nome do item ', 'item'),
    ]) {
      final pfx = entry.$1;
      final refType = entry.$2;
      if (normalizedText.startsWith(pfx) &&
          !normalizedText.contains(' para ')) {
        final raw = normalizedText.substring(pfx.length).trim();
        if (raw.isNotEmpty) {
          final param =
              refType == 'gravacao' ? _gravacaoRefParam(raw) : 'item $raw';
          debugPrint(
            '[VoiceParser] raw=$originalText '
            'matched_rule=renomearGravacao_direct '
            'priority=high context=recordings '
            'referenceType=$refType requestedTarget=$raw',
          );
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.renomearGravacao,
            tipoComando: 'renomear_gravacao',
            acaoExecutada: 'Renomear gravação',
            parametro: param,
          );
        }
      }
    }

    // "frase [texto]" / "nome [texto]" — fill the custom command phrase field.
    // Project-name patterns (starting with "do projeto" or "projeto") must NOT
    // be captured here; they fall through to the main interpret() body where
    // _extractAfterAny handles them as definirNomeProjeto.
    for (final prefix in const ['frase ', 'nome ']) {
      if (normalizedText.startsWith(prefix)) {
        final texto = normalizedText.replaceFirst(prefix, '').trim();
        if (texto.isNotEmpty) {
          if (prefix == 'nome ' &&
              (texto.startsWith('do projeto') ||
                  texto.startsWith('projeto') ||
                  texto.startsWith('da gravacao') ||
                  texto.startsWith('da gravação') ||
                  texto.startsWith('do item'))) {
            // Yield to definirNomeProjeto in main interpret().
            debugPrint(
              '[VoiceParser] raw=$originalText '
              'matched_rule=nome_project_passthrough '
              'priority=high context=project type=definirNomeProjeto(deferred)',
            );
            break;
          }
          debugPrint(
            '[VoiceParser] raw=$originalText '
            'matched_rule=preencherFraseComando '
            'priority=high context=settings type=preencherFraseComando',
          );
          return _recognized(
            originalText,
            normalizedText,
            VoiceCommandType.preencherFraseComando,
            tipoComando: 'preencher_frase_comando',
            acaoExecutada: 'Preencher frase',
            parametro: texto,
          );
        }
      }
    }

    // "salvar comando" / "confirmar comando"
    if (_equalsAny(normalizedText, const [
      'salvar comando',
      'confirmar comando',
      'salvar comando personalizado',
      'confirmar comando personalizado',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.salvarComandoPersonalizado,
        tipoComando: 'salvar_comando_personalizado',
        acaoExecutada: 'Salvar comando personalizado',
      );
    }

    // Bare "tempo de silencio" / "sensibilidade de silencio" — consult current value
    if (_equalsAny(normalizedText, const [
      'tempo de silencio',
      'tempo silencio',
      'qual o tempo de silencio',
      'quanto e o tempo de silencio',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.consultarTempoSilencio,
        tipoComando: 'consultar_tempo_silencio',
        acaoExecutada: 'Consultar tempo de silêncio',
      );
    }

    // "aumentar/mais tempo de silencio" (and article variants)
    if (_containsAny(normalizedText, const [
          'aumentar tempo de silencio',
          'mais tempo de silencio',
          'subir tempo de silencio',
        ]) ||
        (normalizedText.contains('tempo de silencio') &&
            (normalizedText.contains('aumentar') ||
                normalizedText.contains('subir') ||
                normalizedText.contains('mais')))) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.ajustarTempoSilencio,
        tipoComando: 'ajustar_tempo_silencio',
        acaoExecutada: 'Aumentar tempo de silêncio',
        parametro: 'aumentar',
      );
    }
    // "diminuir/menos tempo de silencio" (and article variants)
    if (_containsAny(normalizedText, const [
          'diminuir tempo de silencio',
          'menos tempo de silencio',
          'baixar tempo de silencio',
          'reduzir tempo de silencio',
        ]) ||
        (normalizedText.contains('tempo de silencio') &&
            (normalizedText.contains('diminuir') ||
                normalizedText.contains('baixar') ||
                normalizedText.contains('reduzir') ||
                normalizedText.contains('menos')))) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.ajustarTempoSilencio,
        tipoComando: 'ajustar_tempo_silencio',
        acaoExecutada: 'Diminuir tempo de silêncio',
        parametro: 'diminuir',
      );
    }

    // Bare "sensibilidade de silencio" — consult current value
    if (_equalsAny(normalizedText, const [
      'sensibilidade de silencio',
      'sensibilidade do silencio',
      'sensibilidade',
      'qual a sensibilidade de silencio',
      'quanto e a sensibilidade de silencio',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.consultarSensibilidadeSilencio,
        tipoComando: 'consultar_sensibilidade_silencio',
        acaoExecutada: 'Consultar sensibilidade de silêncio',
      );
    }

    // "aumentar/mais sensibilidade" (article variants + "mais sensivel")
    if (_containsAny(normalizedText, const [
      'aumentar sensibilidade',
      'aumentar a sensibilidade',
      'mais sensivel',
      'mais sensibilidade',
      'mais a sensibilidade',
      'aumentar limiar',
      'subir sensibilidade',
      'subir a sensibilidade',
      'subir limiar',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.ajustarSensibilidadeSilencio,
        tipoComando: 'ajustar_sensibilidade_silencio',
        acaoExecutada: 'Aumentar sensibilidade de silêncio',
        parametro: 'aumentar',
      );
    }
    // "diminuir/baixar/menos sensibilidade" (article variants + "menos sensivel")
    if (_containsAny(normalizedText, const [
      'diminuir sensibilidade',
      'diminuir a sensibilidade',
      'baixar sensibilidade',
      'baixar a sensibilidade',
      'reduzir sensibilidade',
      'reduzir a sensibilidade',
      'menos sensivel',
      'menos sensibilidade',
      'menos a sensibilidade',
      'diminuir limiar',
      'baixar limiar',
      'reduzir limiar',
      'sensibilidade baixar',
      'sensibilidade diminuir',
    ])) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.ajustarSensibilidadeSilencio,
        tipoComando: 'ajustar_sensibilidade_silencio',
        acaoExecutada: 'Diminuir sensibilidade de silêncio',
        parametro: 'diminuir',
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

    // Patterns that extract a new name directly when the recording is already
    // known (i.e., in DetalhesGravacao). No current-name required.
    final renomearPara = _extractAfterAny(normalizedText, const [
      'renomear para',
      'renomear gravacao para',
      'mudar nome para',
      'alterar nome para',
      'chamar gravacao de',
      'chamar de',
    ]);
    if (renomearPara != null) {
      return _recognized(
        originalText,
        normalizedText,
        VoiceCommandType.renomearGravacao,
        tipoComando: 'renomear_gravacao',
        acaoExecutada: 'Renomear gravacao',
        parametroSecundario: _cleanShortName(renomearPara),
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

  // Matches only when the text IS the pattern or STARTS WITH the pattern.
  // Safer than _containsAny for navigation commands: prevents long ambient
  // phrases from matching a keyword buried in the middle.
  bool _startsWithAny(String text, List<String> patterns) {
    return patterns.any(
      (p) => text == p || text.startsWith('$p '),
    );
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

  String _gravacaoRefParam(String raw) {
    const wordNumbers = {
      'um', 'uma', 'dois', 'duas', 'tres', 'quatro', 'cinco',
      'seis', 'sete', 'oito', 'nove',
    };
    if (RegExp(r'^[0-9]+$').hasMatch(raw) || wordNumbers.contains(raw)) {
      return 'gravacao $raw';
    }
    return raw;
  }

  (String, String)? _extractRenameRecording(String text) {
    // Aceita "renomear gravacao X para Y", "renomear item X para Y",
    // "mudar nome da gravacao X para Y", "alterar nome da gravacao X para Y",
    // "trocar nome da gravacao X para Y" e variantes com audio/faixa.
    final match = RegExp(
      r'^(?:renomear|nomear|mudar nome da|alterar nome da|trocar nome da) (?:gravacao|item|audio|faixa) (.+) para (.+)$',
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    final atual = match.group(1)?.trim();
    final novo = match.group(2)?.trim();

    if (atual == null || atual.isEmpty || novo == null || novo.isEmpty) {
      return null;
    }

    return (atual, novo);
  }

  // Returns (nomeProjeto, novoNome) where nomeProjeto can be null (use current
  // project). Accepts article "o" and "mudar [o] nome d[ao] [o] projeto".
  (String?, String)? _extractRenameProject(String text) {
    // With explicit project name.
    final withName = RegExp(
      r'^(?:renomear|nomear|editar|alterar) (?:o )?projeto (.+) para (.+)$'
      r'|^mudar (?:o )?nome d[ao] (?:o )?projeto (.+) para (.+)$',
    ).firstMatch(text);
    if (withName != null) {
      final atual =
          (withName.group(1) ?? withName.group(3))?.trim();
      final novo =
          (withName.group(2) ?? withName.group(4))?.trim();
      if (atual != null && atual.isNotEmpty && novo != null && novo.isNotEmpty) {
        return (atual, novo);
      }
    }

    // Without explicit project name — use the current project (owner decides).
    final withoutName = RegExp(
      r'^(?:renomear|alterar) (?:o )?projeto para (.+)$'
      r'|^mudar (?:o )?nome d[ao] (?:o )?projeto para (.+)$',
    ).firstMatch(text);
    if (withoutName != null) {
      final novo =
          (withoutName.group(1) ?? withoutName.group(2))?.trim();
      if (novo != null && novo.isNotEmpty) {
        return (null, novo);
      }
    }

    return null;
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

  static const Map<String, int> _wordNumbers = {
    'dois': 2,
    'duas': 2,
    'tres': 3,
    'quatro': 4,
    'cinco': 5,
    'seis': 6,
    'sete': 7,
    'oito': 8,
    'nove': 9,
    'dez': 10,
    'onze': 11,
    'doze': 12,
  };

  int? _extractTempoSilencio(String text) {
    // Numeric match — many phrase variations
    final numericPatterns = [
      RegExp(
        r'^(definir |ajustar |alterar |usar )?tempo de silencio (para )?(\d{1,2})( segundos?)?$',
      ),
      RegExp(
        r'^(definir |ajustar |alterar )?silencio (para )?(\d{1,2})( segundos?)?$',
      ),
      RegExp(
        r'^(definir |ajustar |alterar )?parada (?:automatica|por silencio) (?:para |em )?(\d{1,2})( segundos?)?$',
      ),
      RegExp(r'^parar apos (\d{1,2}) segundos?( de silencio)?$'),
      RegExp(r'^(\d{1,2}) segundos? de silencio$'),
    ];

    for (final pattern in numericPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        // Try last non-null group that parses as int
        for (var i = match.groupCount; i >= 1; i--) {
          final v = int.tryParse(match.group(i) ?? '');
          if (v != null) return v.clamp(3, 12).toInt();
        }
      }
    }

    // Word-number match — "definir silêncio para três segundos" etc.
    for (final entry in _wordNumbers.entries) {
      final word = entry.key;
      final wordPatterns = [
        RegExp(
          '^(definir |ajustar |alterar |usar )?tempo de silencio (para )?$word( segundos?)?\$',
        ),
        RegExp(
          '^(definir |ajustar |alterar )?silencio (para )?$word( segundos?)?\$',
        ),
        RegExp(
          '^(definir |ajustar |alterar )?parada (?:automatica|por silencio) (?:para |em )?$word( segundos?)?\$',
        ),
        RegExp('^parar apos $word segundos?( de silencio)?\$'),
        RegExp('^$word segundos? de silencio\$'),
      ];
      for (final pattern in wordPatterns) {
        if (pattern.hasMatch(text)) {
          return entry.value.clamp(3, 12).toInt();
        }
      }
    }

    return null;
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
