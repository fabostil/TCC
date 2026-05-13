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
  });

  final String originalText;
  final String normalizedText;
  final VoiceCommandType type;
  final bool recognized;
  final String tipoComando;
  final String? acaoExecutada;

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

    if (_containsAny(normalizedText, const ['parar reproducao'])) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.pararReproducao,
        tipoComando: 'parar_reproducao',
        acaoExecutada: 'Parar reproducao',
      );
    }

    if (_containsAny(normalizedText, const ['reproduzir']) ||
        _containsWord(normalizedText, 'tocar')) {
      return _recognized(
        text,
        normalizedText,
        VoiceCommandType.reproduzirGravacao,
        tipoComando: 'reproduzir_gravacao',
        acaoExecutada: 'Reproduzir gravacao',
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
  }) {
    return CommandResult(
      originalText: originalText,
      normalizedText: normalizedText,
      type: type,
      recognized: true,
      tipoComando: tipoComando,
      acaoExecutada: acaoExecutada,
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
}
