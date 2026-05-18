import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/voice_status_bar.dart';
import '../../../models/usuario.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../coordination/contextual_voice_listening_mixin.dart';
import '../coordination/voice_command_dispatcher.dart';
import '../coordination/voice_page_owners.dart';
import '../services/command_service.dart';
import 'login_page.dart';

class VoicePage extends StatefulWidget {
  final Usuario usuario;

  const VoicePage({super.key, required this.usuario});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage>
    with ContextualVoiceListeningMixin<VoicePage> {
  String text = 'Pressione o microfone e fale';
  String ultimoComando = 'Nenhum comando executado ainda.';

  @override
  String get voiceOwnerId => VoicePageOwners.voicePage;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo... fale um comando.';

  @override
  String get voiceErrorPrompt => 'Nao foi possivel reconhecer a fala.';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  void initState() {
    super.initState();
    voiceCommandDispatcher = VoiceCommandDispatcher(
      handlers: {
        VoiceCommandType.limparTexto: _handleLimparTexto,
        VoiceCommandType.listarGravacoes: _handleAbrirGravacoes,
        VoiceCommandType.abrirNovoProjeto: _handleAbrirNovoProjeto,
        VoiceCommandType.abrirDashboard: _handleAbrirDashboard,
        VoiceCommandType.abrirProjetos: _handleAbrirProjetos,
        VoiceCommandType.abrirGravacoes: _handleAbrirGravacoes,
        VoiceCommandType.abrirConfiguracoes: _handleAbrirConfiguracoes,
        VoiceCommandType.abrirAssistente: _handleAssistenteAberto,
        VoiceCommandType.abrirEditor: _handleAbrirEditor,
        VoiceCommandType.abrirHistorico: _handleAbrirHistorico,
        VoiceCommandType.voltar: _handleVoltar,
        VoiceCommandType.sair: _handleSair,
      },
      onFallback: _dispatchVoicePageCommand,
    );
    voiceStatusMessage = ultimoComando;
  }

  Future<VoiceCommandPageResult> _dispatchVoicePageCommand(
    CommandResult resultado,
  ) async {
    _atualizarTextoReconhecido(resultado);

    switch (resultado.type) {
      case VoiceCommandType.iniciarGravacao:
        return _comandoReconhecido('Comando reconhecido: iniciar gravacao');
      case VoiceCommandType.pausarGravacao:
        return _comandoReconhecido('Comando reconhecido: pausar gravacao');
      case VoiceCommandType.retomarGravacao:
        return _comandoReconhecido('Comando reconhecido: retomar gravacao');
      case VoiceCommandType.encerrarGravacao:
        return _comandoReconhecido('Comando reconhecido: encerrar gravacao');
      case VoiceCommandType.criarMarcador:
        return _comandoReconhecido('Comando reconhecido: criar marcador');
      case VoiceCommandType.pararReproducao:
        return _comandoReconhecido('Comando reconhecido: parar reproducao');
      case VoiceCommandType.reproduzirGravacao:
        return _comandoReconhecido('Comando reconhecido: reproduzir gravacao');
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.confirmarAcao:
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.ativarControleVoz:
      case VoiceCommandType.desativarControleVoz:
      case VoiceCommandType.ativarEscutaContinua:
      case VoiceCommandType.desativarEscutaContinua:
      case VoiceCommandType.ativarFeedbackSonoro:
      case VoiceCommandType.desativarFeedbackSonoro:
      case VoiceCommandType.ativarTemaEscuro:
      case VoiceCommandType.desativarTemaEscuro:
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
        return _comandoReconhecido(
          'Comando contextual. Abra a tela correspondente.',
        );
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.voltar:
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        break;
    }

    final mensagem = voiceCommandController.aiConfigured
        ? 'Comando nao reconhecido pela IA.'
        : 'Comando nao reconhecido. Configure GEMINI_API_KEY para NLU.';
    return _comandoReconhecido(mensagem);
  }

  Future<VoiceCommandPageResult> _handleLimparTexto(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    setState(() {
      text = 'Pressione o microfone e fale';
    });
    return _comandoReconhecido('Texto limpo.');
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboard(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo dashboard...');
    return _navegar(
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetos(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo projetos...');
    return _navegar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjeto(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo criacao de projeto...');
    return _navegar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirGravacoes(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo gravacoes...');
    return _navegar(
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirConfiguracoes(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo configuracoes...');
    return _navegar(
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirHistorico(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Abrindo historico...');
    return _navegar(
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAssistenteAberto(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    return _comandoReconhecido('Assistente de voz ja esta aberto.');
  }

  Future<VoiceCommandPageResult> _handleAbrirEditor(
    CommandResult result,
  ) async {
    _atualizarTextoReconhecido(result);
    return _comandoReconhecido('Abra um projeto para acessar o editor.');
  }

  Future<VoiceCommandPageResult> _handleVoltar(CommandResult result) async {
    _atualizarTextoReconhecido(result);
    _setUltimoComando('Voltando...');

    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleSair(CommandResult result) async {
    _atualizarTextoReconhecido(result);
    await suspendContextualVoiceListening();
    if (mounted) {
      sair();
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _navegar<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      unawaited(Navigator.push(context, route));
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  VoiceCommandPageResult _comandoReconhecido(String mensagem) {
    _setUltimoComando(mensagem);
    return VoiceCommandPageResult.handled(message: mensagem);
  }

  void _setUltimoComando(String mensagem) {
    setState(() {
      ultimoComando = mensagem;
      voiceStatusMessage = mensagem;
    });
  }

  void _atualizarTextoReconhecido(CommandResult result) {
    setState(() {
      text = result.originalText;
    });
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    super.dispose();
  }

  void sair() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ola, ${widget.usuario.nome}'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: sair,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.music_note, size: 56, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text(
              'Assistente de Voz',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use comandos como: iniciar gravacao, pausar gravacao, retomar gravacao ou encerrar gravacao.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                voiceIaPensando ? 'IA pensando...' : ultimoComando,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'micButtonVoicePage',
                  onPressed: toggleContextualVoiceListening,
                  backgroundColor: voiceOuvindo ? Colors.red : Colors.blue,
                  child: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'clearButtonVoicePage',
                  onPressed: () {
                    setState(() {
                      text = 'Pressione o microfone e fale';
                    });
                    _setUltimoComando('Texto limpo.');
                  },
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.clear),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: voiceStatusMessage == null
          ? null
          : VoiceStatusBar(
              message: voiceStatusMessage!,
              listening: voiceOuvindo,
              thinking: voiceIaPensando,
            ),
    );
  }
}
