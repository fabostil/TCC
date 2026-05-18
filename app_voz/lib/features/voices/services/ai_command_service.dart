import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'command_service.dart';

typedef AiHttpPost =
    Future<Map<String, dynamic>> Function(
      Uri uri,
      Map<String, String> headers,
      Map<String, dynamic> body,
      Duration timeout,
    );

class AiCommandService {
  AiCommandService({
    this.apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.model = const String.fromEnvironment(
      'GEMINI_MODEL',
      defaultValue: 'gemini-1.5-flash',
    ),
    this.timeout = const Duration(seconds: 2),
    this.maxRequestsPerMinute = 15,
    AiHttpPost? httpPost,
    CommandService? commandService,
  }) : _httpPost = httpPost ?? _defaultHttpPost,
       _commandService = commandService ?? const CommandService();

  final String apiKey;
  final String model;
  final Duration timeout;
  final int maxRequestsPerMinute;
  final AiHttpPost _httpPost;
  final CommandService _commandService;
  final List<DateTime> _requestTimes = [];

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Future<CommandResult> interpretUnknown(String text) async {
    final normalizedText = _commandService.normalize(text);

    if (normalizedText.isEmpty || !isConfigured || !_canRequest()) {
      return _unknown(text, normalizedText);
    }

    _requestTimes.add(DateTime.now());

    try {
      final response = await _httpPost(
        _buildUri(),
        {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        _buildRequestBody(text),
        timeout,
      ).timeout(timeout);
      final parsed = _extractCommand(response);

      return _mapCommand(text, normalizedText, parsed);
    } catch (_) {
      return _unknown(text, normalizedText);
    }
  }

  Uri _buildUri() {
    return Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );
  }

  Map<String, dynamic> _buildRequestBody(String text) {
    return {
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': text},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 96,
        'responseMimeType': 'application/json',
      },
    };
  }

  bool _canRequest() {
    final now = DateTime.now();
    _requestTimes.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );

    return _requestTimes.length < maxRequestsPerMinute;
  }

  _AiParsedCommand? _extractCommand(Map<String, dynamic> response) {
    final candidates = response['candidates'];

    if (candidates is! List || candidates.isEmpty) {
      return null;
    }

    final candidate = candidates.first;

    if (candidate is! Map<String, dynamic>) {
      return null;
    }

    final content = candidate['content'];

    if (content is! Map<String, dynamic>) {
      return null;
    }

    final parts = content['parts'];

    if (parts is! List || parts.isEmpty) {
      return null;
    }

    final part = parts.first;

    if (part is! Map<String, dynamic>) {
      return null;
    }

    final rawText = part['text'];

    if (rawText is! String || rawText.trim().isEmpty) {
      return null;
    }

    final parsed = jsonDecode(_stripJsonFence(rawText));

    if (parsed is! Map<String, dynamic>) {
      return null;
    }

    final action = parsed['action'];

    if (action is! String) {
      return null;
    }

    return _AiParsedCommand(
      action: action.trim(),
      parametro: _readOptionalString(parsed, 'parametro'),
      parametroSecundario: _readOptionalString(parsed, 'parametro_secundario'),
    );
  }

  String? _readOptionalString(Map<String, dynamic> parsed, String key) {
    final value = parsed[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }

  String _stripJsonFence(String value) {
    final trimmed = value.trim();

    if (!trimmed.startsWith('```')) {
      return trimmed;
    }

    return trimmed
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  CommandResult _mapCommand(
    String originalText,
    String normalizedText,
    _AiParsedCommand? parsed,
  ) {
    switch (parsed?.action) {
      case 'record_start':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.iniciarGravacao,
          tipoComando: 'iniciar_gravacao',
          acaoExecutada: 'Iniciar gravacao',
        );
      case 'record_pause':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.pausarGravacao,
          tipoComando: 'pausar_gravacao',
          acaoExecutada: 'Pausar gravacao',
        );
      case 'record_resume':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.retomarGravacao,
          tipoComando: 'retomar_gravacao',
          acaoExecutada: 'Retomar gravacao',
        );
      case 'record_stop':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.encerrarGravacao,
          tipoComando: 'encerrar_gravacao',
          acaoExecutada: 'Encerrar gravacao',
        );
      case 'playback_play':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.reproduzirGravacao,
          tipoComando: 'reproduzir_gravacao',
          acaoExecutada: 'Reproduzir gravacao',
          parametro: parsed?.parametro,
        );
      case 'playback_stop':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.pararReproducao,
          tipoComando: 'parar_reproducao',
          acaoExecutada: 'Parar reproducao',
        );
      case 'marker_create':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.criarMarcador,
          tipoComando: 'criar_marcador',
          acaoExecutada: 'Criar marcador',
        );
      case 'clear_text':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.limparTexto,
          tipoComando: 'limpar_texto',
          acaoExecutada: 'Limpar texto reconhecido',
        );
      case 'nav_new_project':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirNovoProjeto,
          tipoComando: 'abrir_novo_projeto',
          acaoExecutada: 'Abrir novo projeto',
        );
      case 'project_create':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.criarProjeto,
          tipoComando: 'criar_projeto',
          acaoExecutada: 'Criar projeto',
        );
      case 'project_cancel':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.cancelarProjeto,
          tipoComando: 'cancelar_projeto',
          acaoExecutada: 'Cancelar projeto',
        );
      case 'project_name_set':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.definirNomeProjeto,
          tipoComando: 'definir_nome_projeto',
          acaoExecutada: 'Definir nome do projeto',
          parametro: parsed?.parametro,
        );
      case 'project_name_replace':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.substituirNomeProjeto,
          tipoComando: 'substituir_nome_projeto',
          acaoExecutada: 'Substituir nome do projeto',
          parametro: parsed?.parametro,
        );
      case 'project_description_set':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.definirDescricaoProjeto,
          tipoComando: 'definir_descricao_projeto',
          acaoExecutada: 'Definir descricao do projeto',
          parametro: parsed?.parametro,
        );
      case 'project_description_replace':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.substituirDescricaoProjeto,
          tipoComando: 'substituir_descricao_projeto',
          acaoExecutada: 'Substituir descricao do projeto',
          parametro: parsed?.parametro,
        );
      case 'project_open_named':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirProjetoPorNome,
          tipoComando: 'abrir_projeto_por_nome',
          acaoExecutada: 'Abrir projeto por nome',
          parametro: parsed?.parametro,
        );
      case 'project_rename_named':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.renomearProjeto,
          tipoComando: 'renomear_projeto',
          acaoExecutada: 'Renomear projeto',
          parametro: parsed?.parametro,
          parametroSecundario: parsed?.parametroSecundario,
        );
      case 'recording_delete_named':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.excluirGravacao,
          tipoComando: 'excluir_gravacao',
          acaoExecutada: 'Excluir gravacao',
          parametro: parsed?.parametro,
        );
      case 'recording_rename_named':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.renomearGravacao,
          tipoComando: 'renomear_gravacao',
          acaoExecutada: 'Renomear gravacao',
          parametro: parsed?.parametro,
          parametroSecundario: parsed?.parametroSecundario,
        );
      case 'recording_details_named':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirDetalhesGravacao,
          tipoComando: 'abrir_detalhes_gravacao',
          acaoExecutada: 'Abrir detalhes da gravacao',
          parametro: parsed?.parametro,
        );
      case 'settings_voice_on':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.ativarControleVoz,
          tipoComando: 'ativar_controle_voz',
          acaoExecutada: 'Ativar controle por voz',
        );
      case 'settings_voice_off':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.desativarControleVoz,
          tipoComando: 'desativar_controle_voz',
          acaoExecutada: 'Desativar controle por voz',
        );
      case 'settings_continuous_on':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.ativarEscutaContinua,
          tipoComando: 'ativar_escuta_continua',
          acaoExecutada: 'Ativar escuta continua',
        );
      case 'settings_continuous_off':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.desativarEscutaContinua,
          tipoComando: 'desativar_escuta_continua',
          acaoExecutada: 'Desativar escuta continua',
        );
      case 'settings_feedback_on':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.ativarFeedbackSonoro,
          tipoComando: 'ativar_feedback_sonoro',
          acaoExecutada: 'Ativar feedback sonoro',
        );
      case 'settings_feedback_off':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.desativarFeedbackSonoro,
          tipoComando: 'desativar_feedback_sonoro',
          acaoExecutada: 'Desativar feedback sonoro',
        );
      case 'settings_dark_theme_on':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.ativarTemaEscuro,
          tipoComando: 'ativar_tema_escuro',
          acaoExecutada: 'Ativar tema escuro',
        );
      case 'settings_dark_theme_off':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.desativarTemaEscuro,
          tipoComando: 'desativar_tema_escuro',
          acaoExecutada: 'Ativar tema claro',
        );
      case 'settings_silence_stop_on':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.ativarParadaSilencio,
          tipoComando: 'ativar_parada_silencio',
          acaoExecutada: 'Ativar parada por silencio',
        );
      case 'settings_silence_stop_off':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.desativarParadaSilencio,
          tipoComando: 'desativar_parada_silencio',
          acaoExecutada: 'Desativar parada por silencio',
        );
      case 'settings_silence_time_set':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.definirTempoSilencio,
          tipoComando: 'definir_tempo_silencio',
          acaoExecutada: 'Definir tempo de silencio',
          parametro: parsed?.parametro,
        );
      case 'nav_editor':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirEditor,
          tipoComando: 'abrir_editor',
          acaoExecutada: 'Abrir editor',
        );
      case 'nav_dashboard':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirDashboard,
          tipoComando: 'abrir_dashboard',
          acaoExecutada: 'Abrir dashboard',
        );
      case 'nav_projects':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirProjetos,
          tipoComando: 'abrir_projetos',
          acaoExecutada: 'Abrir projetos',
        );
      case 'nav_recordings':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirGravacoes,
          tipoComando: 'abrir_gravacoes',
          acaoExecutada: 'Abrir gravacoes',
        );
      case 'nav_settings':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirConfiguracoes,
          tipoComando: 'abrir_configuracoes',
          acaoExecutada: 'Abrir configuracoes',
        );
      case 'nav_assistant':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirAssistente,
          tipoComando: 'abrir_assistente',
          acaoExecutada: 'Abrir assistente',
        );
      case 'nav_history':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.abrirHistorico,
          tipoComando: 'abrir_historico',
          acaoExecutada: 'Abrir historico',
        );
      case 'nav_back':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.voltar,
          tipoComando: 'voltar',
          acaoExecutada: 'Voltar tela',
        );
      case 'confirm_action':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.confirmarAcao,
          tipoComando: 'confirmar_acao',
          acaoExecutada: 'Confirmar acao',
        );
      case 'cancel_action':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.cancelarAcao,
          tipoComando: 'cancelar_acao',
          acaoExecutada: 'Cancelar acao',
        );
      case 'logout':
        return _recognized(
          originalText,
          normalizedText,
          VoiceCommandType.sair,
          tipoComando: 'sair',
          acaoExecutada: 'Sair',
        );
      default:
        return _unknown(originalText, normalizedText);
    }
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

  static Future<Map<String, dynamic>> _defaultHttpPost(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final client = HttpClient();

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));

      final response = await request.close().timeout(timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Gemini API returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final decoded = jsonDecode(responseBody);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Gemini response is not a JSON object');
      }

      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

class _AiParsedCommand {
  const _AiParsedCommand({
    required this.action,
    this.parametro,
    this.parametroSecundario,
  });

  final String action;
  final String? parametro;
  final String? parametroSecundario;
}

const String _systemPrompt = '''
Voce e o modulo NLU de um app Flutter voice-first para producao musical.
Responda exclusivamente com JSON valido, sem Markdown, sem explicacoes e sem texto adicional.
Formato obrigatorio: {"action":"<intent>","parametro":"<valor opcional>","parametro_secundario":"<valor opcional>"}
Quando nao houver parametro, omita a chave ou use string vazia.

Regras de parametros:
- Para nomes curtos, extraia somente o nome final. Exemplo: "eu quero que voce coloque o nome abacate" -> parametro "abacate".
- Para abrir, tocar, excluir ou renomear itens por nome, extraia o nome do projeto/gravacao.
- Para renomear gravacao, use parametro como nome atual e parametro_secundario como novo nome.
- Para descricao de projeto, reescreva o parametro em portugues claro e formal, sem mudar o sentido.
- Para tempo de silencio, use parametro numerico entre 3 e 12.

Intents permitidas:
- record_start: iniciar gravacao, gravar ideia, capturar audio.
- record_pause: pausar gravacao.
- record_resume: continuar ou retomar gravacao.
- record_stop: parar, finalizar ou salvar gravacao.
- playback_play: reproduzir ou tocar gravacao.
- playback_stop: parar reproducao.
- marker_create: criar marcador.
- clear_text: limpar texto reconhecido.
- project_name_set: definir ou preencher nome de projeto.
- project_description_set: definir ou preencher descricao de projeto.
- project_name_replace: substituir o nome do projeto por outro valor.
- project_description_replace: substituir a descricao do projeto por outro valor.
- project_create: salvar ou criar o projeto atual.
- project_cancel: cancelar a criacao do projeto atual.
- project_open_named: abrir um projeto pelo nome.
- project_rename_named: renomear projeto; parametro e nome atual, parametro_secundario e novo nome.
- recording_delete_named: excluir/remover/apagar gravacao pelo nome.
- recording_rename_named: renomear gravacao pelo nome.
- recording_details_named: abrir detalhes, informacoes ou metadados de gravacao pelo nome.
- settings_voice_on: ativar comandos ou controle por voz.
- settings_voice_off: desativar comandos ou controle por voz.
- settings_continuous_on: ativar escuta continua.
- settings_continuous_off: desativar escuta continua.
- settings_feedback_on: ativar feedback sonoro.
- settings_feedback_off: desativar feedback sonoro.
- settings_dark_theme_on: ativar tema escuro, modo escuro ou aparencia escura.
- settings_dark_theme_off: ativar tema claro, modo claro ou aparencia clara.
- settings_silence_stop_on: ativar parada por silencio.
- settings_silence_stop_off: desativar parada por silencio.
- settings_silence_time_set: definir tempo de silencio em segundos.
- nav_new_project: abrir formulario de novo projeto, sem salvar.
- nav_editor: abrir editor, gravador ou tela de edicao de um projeto.
- nav_dashboard: abrir dashboard.
- nav_dashboard: ver metricas, numeros, resumo, produtividade ou desempenho.
- nav_projects: abrir projetos.
- nav_recordings: abrir gravacoes.
- nav_settings: abrir configuracoes.
- nav_assistant: abrir assistente de voz.
- nav_history: abrir historico.
- nav_history: ver atividade recente, linha do tempo, ultimas acoes ou historico de uso.
- nav_back: voltar tela.
- confirm_action: confirmar uma acao pendente, como exclusao.
- cancel_action: cancelar uma acao pendente, como exclusao.
- logout: sair da conta.
- unknown: quando nao houver intencao segura.

Nunca invente acoes fora da lista.
Se houver ambiguidade, use {"action":"unknown"}.
''';
