import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import 'login_page.dart';
import '../controllers/voice_command_controller.dart';
import '../services/command_service.dart';
import '../services/speech_service.dart';

class VoicePage extends StatefulWidget {
  final Usuario usuario;

  const VoicePage({super.key, required this.usuario});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService speech = SpeechService();
  final VoiceCommandController commandController = VoiceCommandController();

  bool listening = false;
  bool iaPensando = false;
  String text = 'Pressione o microfone e fale';
  String ultimoComando = 'Nenhum comando executado ainda.';

  Future<void> toggleListening() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!configuracao.comandosVozAtivos) {
      setState(() {
        listening = false;
        text = 'Comandos de voz desativados.';
        ultimoComando =
            'Ative o controle por voz em Configurações para usar o assistente.';
      });
      return;
    }

    if (!listening) {
      setState(() {
        listening = true;
        text = 'Ouvindo... fale um comando.';
        ultimoComando = 'Aguardando comando de voz...';
      });

      await speech.startListening(
        onResult: (result) {
          setState(() {
            text = result;
          });

          unawaited(handleVoiceCommand(result));
        },
        onStatus: (status) {
          if (!mounted) {
            return;
          }

          if (status == 'listening') {
            setState(() {
              listening = true;
              ultimoComando = 'Estou ouvindo...';
            });
          }

          if (status == 'done' || status == 'notListening') {
            setState(() {
              listening = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }

          if (error == 'error_speech_timeout') {
            setState(() {
              listening = false;
              text = 'Nenhuma fala detectada. Tente novamente.';
              ultimoComando = 'Tempo de escuta encerrado sem comando.';
            });
            return;
          }

          setState(() {
            listening = false;
            text = 'Não foi possível reconhecer a fala.';
            ultimoComando = 'Erro no reconhecimento de voz: $error';
          });
        },
      );
    } else {
      await speech.stopListening();

      setState(() {
        listening = false;
        text = 'Pressione o microfone e fale';
        ultimoComando = 'Escuta encerrada.';
      });
    }
  }

  void clearText() {
    setState(() {
      text = 'Pressione o microfone e fale';
      ultimoComando = 'Texto limpo.';
    });
  }

  Future<void> handleVoiceCommand(String command) async {
    final resultadoController = await commandController.interpret(
      command,
      onAiStarted: () {
        if (!mounted) {
          return;
        }

        setState(() {
          iaPensando = true;
          ultimoComando = 'IA pensando...';
        });
      },
    );
    final resultado = resultadoController.commandResult;

    if (!mounted) {
      return;
    }

    if (iaPensando) {
      setState(() {
        iaPensando = false;
      });
    }

    if (resultado.normalizedText.isEmpty) {
      return;
    }

    if (resultado.recognized) {
      registrarComandoVoz(
        command,
        tipoComando: resultado.tipoComando,
        acaoExecutada: resultado.acaoExecutada,
      );
    }

    switch (resultado.type) {
      case VoiceCommandType.limparTexto:
        clearText();
        return;
      case VoiceCommandType.iniciarGravacao:
        setState(() {
          ultimoComando = 'Comando reconhecido: iniciar gravacao';
        });
        return;
      case VoiceCommandType.pausarGravacao:
        setState(() {
          ultimoComando = 'Comando reconhecido: pausar gravacao';
        });
        return;
      case VoiceCommandType.retomarGravacao:
        setState(() {
          ultimoComando = 'Comando reconhecido: retomar gravacao';
        });
        return;
      case VoiceCommandType.encerrarGravacao:
        setState(() {
          ultimoComando = 'Comando reconhecido: encerrar gravacao';
        });
        return;
      case VoiceCommandType.listarGravacoes:
        _abrirGravacoes();
        return;
      case VoiceCommandType.abrirNovoProjeto:
        _abrirNovoProjeto();
        return;
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.renomearProjeto:
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
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
        setState(() {
          ultimoComando = 'Comando contextual. Abra a tela correspondente.';
        });
        return;
      case VoiceCommandType.criarMarcador:
        setState(() {
          ultimoComando = 'Comando reconhecido: criar marcador';
        });
        return;
      case VoiceCommandType.pararReproducao:
        setState(() {
          ultimoComando = 'Comando reconhecido: parar reproducao';
        });
        return;
      case VoiceCommandType.reproduzirGravacao:
        setState(() {
          ultimoComando = 'Comando reconhecido: reproduzir gravacao';
        });
        return;
      case VoiceCommandType.abrirDashboard:
        _abrirDashboard();
        return;
      case VoiceCommandType.abrirProjetos:
        _abrirProjetos();
        return;
      case VoiceCommandType.abrirGravacoes:
        _abrirGravacoes();
        return;
      case VoiceCommandType.abrirConfiguracoes:
        _abrirConfiguracoes();
        return;
      case VoiceCommandType.abrirAssistente:
        setState(() {
          ultimoComando = 'Assistente de voz ja esta aberto.';
        });
        return;
      case VoiceCommandType.abrirEditor:
        setState(() {
          ultimoComando = 'Abra um projeto para acessar o editor.';
        });
        return;
      case VoiceCommandType.abrirHistorico:
        _abrirHistorico();
        return;
      case VoiceCommandType.voltar:
        _voltar();
        return;
      case VoiceCommandType.sair:
        sair();
        return;
      case VoiceCommandType.desconhecido:
        break;
    }

    registrarComandoVoz(
      command,
      tipoComando: resultado.tipoComando,
      statusReconhecimento: resultado.statusReconhecimento,
    );

    setState(() {
      iaPensando = false;
      ultimoComando = commandController.aiConfigured
          ? 'Comando nao reconhecido pela IA.'
          : 'Comando nao reconhecido. Configure GEMINI_API_KEY para NLU.';
    });
  }

  void _abrirDashboard() {
    setState(() {
      ultimoComando = 'Abrindo dashboard...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
  }

  void _abrirProjetos() {
    setState(() {
      ultimoComando = 'Abrindo projetos...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  void _abrirNovoProjeto() {
    setState(() {
      ultimoComando = 'Abrindo criacao de projeto...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  void _abrirGravacoes() {
    setState(() {
      ultimoComando = 'Abrindo gravacoes...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  void _abrirConfiguracoes() {
    setState(() {
      ultimoComando = 'Abrindo configuracoes...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  void _abrirHistorico() {
    setState(() {
      ultimoComando = 'Abrindo historico...';
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
  }

  void _voltar() {
    setState(() {
      ultimoComando = 'Voltando...';
    });

    Navigator.maybePop(context);
  }

  void registrarComandoVoz(
    String comando, {
    required String tipoComando,
    String statusReconhecimento = 'reconhecido',
    String? acaoExecutada,
  }) {
    unawaited(
      _registrarComandoVozPersistente(
        comando,
        tipoComando: tipoComando,
        statusReconhecimento: statusReconhecimento,
        acaoExecutada: acaoExecutada,
      ),
    );
  }

  Future<void> _registrarComandoVozPersistente(
    String comando, {
    required String tipoComando,
    required String statusReconhecimento,
    String? acaoExecutada,
  }) async {
    final usuarioId = widget.usuario.id;

    if (usuarioId == null) {
      return;
    }

    try {
      await ComandoVozRepository.instance.registrar(
        usuarioId: usuarioId,
        textoReconhecido: comando,
        tipoComando: tipoComando,
        statusReconhecimento: statusReconhecimento,
        acaoExecutada: acaoExecutada,
      );
    } catch (e) {
      debugPrint('Erro ao registrar comando de voz: $e');
    }
  }

  @override
  void dispose() {
    speech.stopListening();
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
        title: Text('Olá, ${widget.usuario.nome}'),
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
              'Use comandos como: iniciar gravação, pausar gravação, retomar gravação ou encerrar gravação.',
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
                color: Colors.deepPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                iaPensando ? 'IA pensando...' : ultimoComando,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'micButtonVoicePage',
                  onPressed: toggleListening,
                  backgroundColor: listening ? Colors.red : Colors.blue,
                  child: Icon(listening ? Icons.mic : Icons.mic_none),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'clearButtonVoicePage',
                  onPressed: clearText,
                  backgroundColor: Colors.grey,
                  child: const Icon(Icons.clear),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
