import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import 'login_page.dart';
import '../services/speech_service.dart';
import '../coordination/voice_listening_coordinator.dart';

class VoicePage extends StatefulWidget {
  final Usuario usuario;

  const VoicePage({super.key, required this.usuario});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  // Chamando as instâncias globais (Singletons) da sua nova arquitetura
  final SpeechService _speechService = SpeechService.instance;
  final VoiceListeningCoordinator _coordinator =
      VoiceListeningCoordinator.instance;

  // Identificador desta tela para o Coordenador saber quem está usando o microfone
  final String _ownerId = 'voice_page_legacy';

  bool listening = false;
  bool _isContinuousListening = false;

  String text = 'Pressione o microfone para iniciar a escuta contínua';
  String ultimoComando = 'Nenhum comando executado ainda.';

  Future<void> toggleListening() async {
    if (!_isContinuousListening) {
      _isContinuousListening = true;
      // Avisa a arquitetura do TCC que esta página assumiu o controle do microfone
      _coordinator.claimListening(_ownerId);
      _iniciarEscutaContinua();
    } else {
      _isContinuousListening = false;
      // Libera o microfone no coordenador
      await _coordinator.releaseAndStop(_ownerId);

      if (mounted) {
        setState(() {
          listening = false;
          text = 'Pressione o microfone e fale';
          ultimoComando = 'Escuta contínua encerrada manualmente.';
        });
      }
    }
  }

  Future<void> _iniciarEscutaContinua() async {
    // Trava de segurança: se o usuário desligou ou a tela fechou
    if (!_isContinuousListening || !mounted) return;

    final started = await _speechService.startListening(
      onResult: (result) {
        setState(() {
          text = result;
        });
        handleVoiceCommand(result);
      },
      onStatus: (status) async {
        if (!mounted) return;

        if (status == 'listening') {
          setState(() {
            listening = true;
            ultimoComando = 'Estou ouvindo ativamente...';
          });
        }

        // O sistema cortou a escuta por silêncio
        if (status == 'done' || status == 'notListening') {
          if (_isContinuousListening) {
            // Usamos o delay padrão definido na sua arquitetura (700ms)
            await Future.delayed(
              _coordinator.restartDelayFor(VoiceRestartReason.normal),
            );
            _iniciarEscutaContinua();
          } else {
            setState(() {
              listening = false;
            });
          }
        }
      },
      onError: (error) async {
        if (!mounted) return;

        // Timeout de silêncio (revezamento)
        if (error == 'error_speech_timeout') {
          if (_isContinuousListening) {
            await Future.delayed(
              _coordinator.restartDelayFor(VoiceRestartReason.normal),
            );
            _iniciarEscutaContinua();
          }
          return;
        }

        setState(() {
          listening = false;
          ultimoComando = 'Tentando reconectar (Erro: $error)...';
        });

        if (_isContinuousListening) {
          // Usamos o delay de erro definido na sua arquitetura (geralmente 2s)
          await Future.delayed(
            _coordinator.restartDelayFor(VoiceRestartReason.afterError),
          );
          _iniciarEscutaContinua();
        }
      },
    );

    // Se o serviço falhou ao iniciar (ex: negou permissão de microfone)
    if (!started && mounted && _isContinuousListening) {
      setState(() {
        listening = false;
        _isContinuousListening = false;
        ultimoComando = 'Falha ao iniciar microfone. Verifique as permissões.';
      });
      _coordinator.releaseOwner(_ownerId);
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

    if (cmd.isEmpty) return;

    if (cmd.contains('limpar')) {
      clearText();
      return;
    }

    if (cmd.contains('iniciar gravação') ||
        cmd.contains('começar gravação') ||
        cmd.contains('gravar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: iniciar gravação';
      });
      return;
    }

    if (cmd.contains('pausar gravação') || cmd.contains('pausar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: pausar gravação';
      });
      return;
    }

    if (cmd.contains('retomar gravação') ||
        cmd.contains('continuar gravação')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: retomar gravação';
      });
      return;
    }

    if (cmd.contains('encerrar gravação') ||
        cmd.contains('parar gravação') ||
        cmd.contains('finalizar gravação')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: encerrar gravação';
      });
      return;
    }

    if (cmd.contains('listar gravações') || cmd.contains('mostrar gravações')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: listar gravações';
      });
      return;
    }

    if (cmd.contains('criar marcador') || cmd.contains('marcar')) {
      setState(() {
        ultimoComando = 'Comando reconhecido: criar marcador';
      });
      return;
    }

    setState(() {
      ultimoComando = 'Comando não mapeado na interface.';
    });
  }

  void sair() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _isContinuousListening = false;
    _coordinator.releaseAndStop(
      _ownerId,
    ); // Libera o Singleton ao destruir a página
    super.dispose();
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
                  backgroundColor: _isContinuousListening
                      ? Colors.red
                      : Colors.blue,
                  child: Icon(
                    _isContinuousListening ? Icons.mic : Icons.mic_none,
                  ),
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
