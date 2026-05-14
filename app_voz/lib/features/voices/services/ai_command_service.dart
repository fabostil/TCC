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
      final action = _extractAction(response);

      return _mapAction(text, normalizedText, action);
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

  String? _extractAction(Map<String, dynamic> response) {
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

    return action is String ? action.trim() : null;
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

  CommandResult _mapAction(
    String originalText,
    String normalizedText,
    String? action,
  ) {
    switch (action) {
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

const String _systemPrompt = '''
Voce e o modulo NLU de um app Flutter voice-first para producao musical.
Responda exclusivamente com JSON valido, sem Markdown, sem explicacoes e sem texto adicional.
Formato obrigatorio: {"action":"<intent>"}

Intents permitidas:
- record_start: iniciar gravacao, gravar ideia, capturar audio.
- record_pause: pausar gravacao.
- record_resume: continuar ou retomar gravacao.
- record_stop: parar, finalizar ou salvar gravacao.
- playback_play: reproduzir ou tocar gravacao.
- playback_stop: parar reproducao.
- marker_create: criar marcador.
- clear_text: limpar texto reconhecido.
- nav_new_project: criar novo projeto ou abrir formulario de novo projeto.
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
- logout: sair da conta.
- unknown: quando nao houver intencao segura.

Nunca invente acoes fora da lista.
Se houver ambiguidade, use {"action":"unknown"}.
''';
