import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import 'login_page.dart';
import '../services/speech_service.dart';

class VoicePage extends StatefulWidget {
  final Usuario usuario;

  const VoicePage({super.key, required this.usuario});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService speech = SpeechService();

  bool listening = false;
  String text = 'Pressione o microfone e fale';
  String ultimoComando = 'Nenhum comando executado ainda.';

  Future<void> toggleListening() async {
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

          handleVoiceCommand(result);
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

  void handleVoiceCommand(String command) {
    final cmd = command.toLowerCase().trim();

    if (cmd.isEmpty) {
      return;
    }

    if (cmd.contains('limpar')) {
      registrarComandoVoz(
        command,
        tipoComando: 'limpar_texto',
        acaoExecutada: 'Limpar texto reconhecido',
      );
      clearText();
      return;
    }

    if (cmd.contains('iniciar gravação') ||
        cmd.contains('começar gravação') ||
        cmd.contains('gravar')) {
      registrarComandoVoz(
        command,
        tipoComando: 'iniciar_gravacao',
        acaoExecutada: 'Reconhecer comando iniciar gravacao',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: iniciar gravação';
      });
      return;
    }

    if (cmd.contains('pausar gravação') || cmd.contains('pausar')) {
      registrarComandoVoz(
        command,
        tipoComando: 'pausar_gravacao',
        acaoExecutada: 'Reconhecer comando pausar gravacao',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: pausar gravação';
      });
      return;
    }

    if (cmd.contains('retomar gravação') ||
        cmd.contains('continuar gravação')) {
      registrarComandoVoz(
        command,
        tipoComando: 'retomar_gravacao',
        acaoExecutada: 'Reconhecer comando retomar gravacao',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: retomar gravação';
      });
      return;
    }

    if (cmd.contains('encerrar gravação') ||
        cmd.contains('parar gravação') ||
        cmd.contains('finalizar gravação')) {
      registrarComandoVoz(
        command,
        tipoComando: 'encerrar_gravacao',
        acaoExecutada: 'Reconhecer comando encerrar gravacao',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: encerrar gravação';
      });
      return;
    }

    if (cmd.contains('listar gravações') || cmd.contains('mostrar gravações')) {
      registrarComandoVoz(
        command,
        tipoComando: 'listar_gravacoes',
        acaoExecutada: 'Reconhecer comando listar gravacoes',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: listar gravações';
      });
      return;
    }

    if (cmd.contains('criar marcador') || cmd.contains('marcar')) {
      registrarComandoVoz(
        command,
        tipoComando: 'criar_marcador',
        acaoExecutada: 'Reconhecer comando criar marcador',
      );
      setState(() {
        ultimoComando = 'Comando reconhecido: criar marcador';
      });
      return;
    }

    registrarComandoVoz(
      command,
      tipoComando: 'desconhecido',
      statusReconhecimento: 'nao_reconhecido',
    );

    setState(() {
      ultimoComando = 'Comando não reconhecido.';
    });
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
                ultimoComando,
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
