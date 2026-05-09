import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../services/audio_recording_service.dart';
import '../../voices/services/speech_service.dart';

class EditorPage extends StatefulWidget {
  final Usuario usuario;

  const EditorPage({super.key, required this.usuario});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final SpeechService speech = SpeechService();
  final AudioRecordingService audioService = AudioRecordingService();

  bool ouvindo = false;
  bool gravando = false;
  bool pausado = false;
  bool reproduzindo = false;
  bool carregandoAudio = false;

  Timer? monitorSilencioTimer;

  double nivelAudioAtual = -160.0;
  int tempoSilencioMs = 0;

  final int limiteSilencioMs = 5000;
  final int intervaloMonitoramentoMs = 500;
  final double limiteSilencioDb = -30.0;

  bool paradaAutomaticaPorSilencio = true;

  String textoReconhecido = 'Pressione o microfone e fale um comando.';
  String statusProjeto = 'Projeto pronto para gravar.';
  String nomeProjeto = 'Projeto sem nome';
  String? caminhoGravacaoAtual;

  final List<Map<String, String>> faixas = [];
  final List<String> historicoComandos = [];

  Future<void> alternarMicrofone() async {
    if (gravando) {
      setState(() {
        statusProjeto =
            'Pare a gravação antes de usar comando de voz. O microfone já está em uso.';
      });
      return;
    }

    if (!ouvindo) {
      setState(() {
        ouvindo = true;
        textoReconhecido = 'Ouvindo... fale um comando.';
        statusProjeto = 'Aguardando comando de voz...';
      });

      await speech.startListening(
        onResult: (resultado) {
          setState(() {
            textoReconhecido = resultado;
            statusProjeto = 'Comando detectado: $resultado';
          });

          interpretarComando(resultado);
        },
        onStatus: (status) {
          if (!mounted) {
            return;
          }

          if (status == 'listening') {
            setState(() {
              ouvindo = true;
              statusProjeto = 'Estou ouvindo...';
            });
          }

          if (status == 'done' || status == 'notListening') {
            setState(() {
              ouvindo = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) {
            return;
          }

          if (error == 'error_speech_timeout') {
            setState(() {
              ouvindo = false;
              textoReconhecido =
                  'Nenhuma fala detectada. Tente falar mais perto do microfone.';
              statusProjeto = 'Tempo de escuta encerrado sem comando.';
            });
            return;
          }

          setState(() {
            ouvindo = false;
            statusProjeto = 'Erro no reconhecimento de voz: $error';
            textoReconhecido = 'Não foi possível reconhecer a fala.';
          });
        },
      );
    } else {
      await speech.stopListening();

      setState(() {
        ouvindo = false;
        textoReconhecido = 'Pressione o microfone e fale um comando.';
        statusProjeto = 'Escuta encerrada.';
      });
    }
  }

  void interpretarComando(String comando) {
    final cmd = comando.toLowerCase().trim();

    if (cmd.isEmpty) {
      return;
    }

    if (cmd.contains('iniciar gravação') ||
        cmd.contains('começar gravação') ||
        cmd.contains('gravar')) {
      iniciarGravacao(comando);
      return;
    }

    if (cmd.contains('pausar gravação') || cmd == 'pausar') {
      pausarGravacao(comando);
      return;
    }

    if (cmd.contains('retomar gravação') ||
        cmd.contains('continuar gravação')) {
      retomarGravacao(comando);
      return;
    }

    if (cmd.contains('encerrar gravação') ||
        cmd.contains('parar gravação') ||
        cmd.contains('finalizar gravação')) {
      encerrarGravacao(comando);
      return;
    }

    if (cmd.contains('parar reprodução')) {
      pararReproducao(comando);
      return;
    }

    if (cmd.contains('reproduzir') || cmd.contains('tocar')) {
      reproduzirProjeto(comando);
      return;
    }

    if (cmd.contains('criar marcador') || cmd.contains('marcar')) {
      criarMarcador(comando);
      return;
    }

    if (cmd.contains('limpar')) {
      limparTexto(comando);
      return;
    }

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Comando não reconhecido',
    );

    setState(() {
      statusProjeto = 'Comando não reconhecido.';
    });
  }

  Future<void> iniciarGravacao(String comando) async {
    if (gravando) {
      setState(() {
        statusProjeto = 'Já existe uma gravação em andamento.';
      });
      return;
    }

    if (ouvindo) {
      await speech.stopListening();

      setState(() {
        ouvindo = false;
      });
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Preparando gravação...';
    });

    try {
      final path = await audioService.startRecording();

      setState(() {
        caminhoGravacaoAtual = path;
        gravando = true;
        pausado = false;
        reproduzindo = false;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        nivelAudioAtual = -160.0;
        statusProjeto = 'Gravação real iniciada.';
        textoReconhecido = 'Gravação iniciada.';
      });

      iniciarMonitoramentoSilencio();

      adicionarHistorico(
        comandoOriginal: comando,
        acao: 'Iniciou gravação real',
      );
    } catch (e) {
      setState(() {
        carregandoAudio = false;
        statusProjeto = 'Erro ao iniciar gravação: $e';
      });
    }
  }

  Future<void> pausarGravacao(String comando) async {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para pausar.';
      });
      return;
    }

    if (pausado) {
      setState(() {
        statusProjeto = 'A gravação já está pausada.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Pausando gravação...';
    });

    try {
      await audioService.pauseRecording();

      setState(() {
        pausado = true;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        statusProjeto = 'Gravação pausada.';
      });

      adicionarHistorico(comandoOriginal: comando, acao: 'Pausou gravação');
    } catch (e) {
      setState(() {
        carregandoAudio = false;
        statusProjeto = 'Erro ao pausar gravação: $e';
      });
    }
  }

  Future<void> retomarGravacao(String comando) async {
    if (!gravando || !pausado) {
      setState(() {
        statusProjeto = 'Não existe gravação pausada para retomar.';
      });
      return;
    }

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Retomando gravação...';
    });

    try {
      await audioService.resumeRecording();

      setState(() {
        pausado = false;
        carregandoAudio = false;
        tempoSilencioMs = 0;
        statusProjeto = 'Gravação retomada.';
      });

      adicionarHistorico(comandoOriginal: comando, acao: 'Retomou gravação');
    } catch (e) {
      setState(() {
        carregandoAudio = false;
        statusProjeto = 'Erro ao retomar gravação: $e';
      });
    }
  }

  Future<void> encerrarGravacao(String comando) async {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para encerrar.';
      });
      return;
    }

    pararMonitoramentoSilencio();

    setState(() {
      carregandoAudio = true;
      statusProjeto = 'Salvando gravação...';
    });

    try {
      final path = await audioService.stopRecording();

      if (path == null || path.isEmpty) {
        setState(() {
          gravando = false;
          pausado = false;
          carregandoAudio = false;
          statusProjeto = 'Não foi possível salvar a gravação.';
        });
        return;
      }

      final numeroFaixa = faixas.length + 1;
      final nomeFaixa = 'Gravação $numeroFaixa';

      final foiParadaAutomatica = comando == 'parada automática por silêncio';

      setState(() {
        gravando = false;
        pausado = false;
        carregandoAudio = false;
        caminhoGravacaoAtual = null;
        tempoSilencioMs = 0;
        nivelAudioAtual = -160.0;
        faixas.add({'nome': nomeFaixa, 'caminho': path});
        statusProjeto = foiParadaAutomatica
            ? '$nomeFaixa salva automaticamente após silêncio.'
            : '$nomeFaixa salva no projeto.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: foiParadaAutomatica
            ? 'Encerrou gravação por silêncio'
            : 'Encerrou gravação real e criou $nomeFaixa',
      );
    } catch (e) {
      setState(() {
        gravando = false;
        pausado = false;
        carregandoAudio = false;
        statusProjeto = 'Erro ao encerrar gravação: $e';
      });
    }
  }

  void iniciarMonitoramentoSilencio() {
    monitorSilencioTimer?.cancel();

    tempoSilencioMs = 0;
    nivelAudioAtual = -160.0;

    monitorSilencioTimer = Timer.periodic(
      Duration(milliseconds: intervaloMonitoramentoMs),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (!gravando || pausado || carregandoAudio) {
          return;
        }

        if (!paradaAutomaticaPorSilencio) {
          return;
        }

        try {
          final amplitude = await audioService.getAmplitude();
          final nivelAtual = amplitude.current;

          setState(() {
            nivelAudioAtual = nivelAtual;
          });

          if (nivelAtual <= limiteSilencioDb) {
            tempoSilencioMs += intervaloMonitoramentoMs;
          } else {
            tempoSilencioMs = 0;
          }

          if (tempoSilencioMs >= limiteSilencioMs) {
            timer.cancel();

            if (mounted && gravando) {
              await encerrarGravacao('parada automática por silêncio');
            }
          }
        } catch (e) {
          debugPrint('Erro ao monitorar silêncio: $e');
        }
      },
    );
  }

  void pararMonitoramentoSilencio() {
    monitorSilencioTimer?.cancel();
    monitorSilencioTimer = null;
    tempoSilencioMs = 0;
  }

  void reproduzirProjeto(String comando) {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Ainda não há gravações para reproduzir.';
      });
      return;
    }

    setState(() {
      reproduzindo = true;
      statusProjeto =
          'Reprodução simulada. Na próxima etapa vamos tocar o áudio real.';
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Iniciou reprodução simulada',
    );
  }

  void pararReproducao(String comando) {
    setState(() {
      reproduzindo = false;
      statusProjeto = 'Reprodução parada.';
    });

    adicionarHistorico(comandoOriginal: comando, acao: 'Parou reprodução');
  }

  void criarMarcador(String comando) {
    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Criou marcador no projeto',
    );

    setState(() {
      statusProjeto = 'Marcador criado no ponto atual.';
    });
  }

  void limparTexto(String comando) {
    setState(() {
      textoReconhecido = 'Pressione o microfone e fale um comando.';
      statusProjeto = 'Texto limpo.';
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Limpou texto reconhecido',
    );
  }

  void adicionarHistorico({
    required String comandoOriginal,
    required String acao,
  }) {
    final registro = '$acao — "$comandoOriginal"';

    setState(() {
      historicoComandos.insert(0, registro);
    });
  }

  Color get corStatus {
    if (gravando && !pausado) {
      return Colors.red;
    }

    if (pausado) {
      return Colors.orange;
    }

    if (reproduzindo) {
      return Colors.green;
    }

    return Colors.deepPurple;
  }

  String get textoStatus {
    if (carregandoAudio) {
      return 'Processando';
    }

    if (gravando && !pausado) {
      return 'Gravando';
    }

    if (pausado) {
      return 'Pausado';
    }

    if (reproduzindo) {
      return 'Reproduzindo';
    }

    return 'Pronto';
  }

  @override
  void dispose() {
    pararMonitoramentoSilencio();
    speech.stopListening();
    audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editor Musical'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cabecalhoProjeto(),
            if (gravando) ...[const SizedBox(height: 18), _modoGravacaoAtivo()],
            const SizedBox(height: 18),
            _linhaDoTempo(),
            const SizedBox(height: 18),
            _controlesManuais(),
            const SizedBox(height: 18),
            _painelVoz(),
            const SizedBox(height: 18),
            _listaFaixas(),
            const SizedBox(height: 18),
            _historico(),
          ],
        ),
      ),
    );
  }

  Widget _cabecalhoProjeto() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: corStatus.withOpacity(0.12),
              child: Icon(Icons.graphic_eq, color: corStatus, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nomeProjeto,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(statusProjeto, style: const TextStyle(fontSize: 15)),
                  if (caminhoGravacaoAtual != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      caminhoGravacaoAtual!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            Chip(
              label: Text(textoStatus),
              avatar: Icon(Icons.circle, size: 12, color: corStatus),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modoGravacaoAtivo() {
    final segundosSilencioRestantes =
        ((limiteSilencioMs - tempoSilencioMs) / 1000).ceil();

    return Card(
      color: Colors.red.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.red.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 56),
            const SizedBox(height: 12),
            Text(
              pausado ? 'GRAVAÇÃO PAUSADA' : 'GRAVANDO...',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pausado
                  ? 'A gravação está pausada.'
                  : 'O microfone está sendo usado para capturar o áudio.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Nível atual: ${nivelAudioAtual.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (paradaAutomaticaPorSilencio && !pausado)
              Text(
                tempoSilencioMs > 0
                    ? 'Silêncio detectado. Parando em $segundosSilencioRestantes s...'
                    : 'Parada automática por silêncio ativada.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: carregandoAudio
                    ? null
                    : () => encerrarGravacao('botão grande parar'),
                icon: const Icon(Icons.stop, size: 32),
                label: const Text(
                  'PARAR GRAVAÇÃO',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Parada automática por silêncio'),
              subtitle: const Text('Encerra após 5 segundos em silêncio.'),
              value: paradaAutomaticaPorSilencio,
              onChanged: carregandoAudio
                  ? null
                  : (value) {
                      setState(() {
                        paradaAutomaticaPorSilencio = value;
                        tempoSilencioMs = 0;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaDoTempo() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Linha do tempo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('00:00'),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: gravando || reproduzindo ? 0.45 : 0.0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('03:00'),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Representação visual simplificada do andamento do projeto.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlesManuais() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => iniciarGravacao('botão gravar'),
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Gravar'),
                ),
                ElevatedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => pausarGravacao('botão pausar'),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
                ElevatedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => retomarGravacao('botão retomar'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
                ElevatedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => encerrarGravacao('botão parar'),
                  icon: const Icon(Icons.stop),
                  label: const Text('Parar'),
                ),
                OutlinedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => reproduzirProjeto('botão reproduzir'),
                  icon: const Icon(Icons.headphones),
                  label: const Text('Reproduzir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _painelVoz() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assistente de voz',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comandos: iniciar gravação, pausar gravação, retomar gravação, encerrar gravação, reproduzir, criar marcador.',
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                textoReconhecido,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FloatingActionButton.extended(
                onPressed: carregandoAudio ? null : alternarMicrofone,
                backgroundColor: ouvindo ? Colors.red : Colors.deepPurple,
                icon: Icon(ouvindo ? Icons.mic : Icons.mic_none),
                label: Text(ouvindo ? 'Parar escuta' : 'Falar comando'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaFaixas() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Faixas do projeto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (faixas.isEmpty)
              const Text('Nenhuma gravação adicionada ainda.'),
            if (faixas.isNotEmpty)
              ...faixas.map(
                (faixa) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.audiotrack),
                  title: Text(faixa['nome'] ?? 'Gravação'),
                  subtitle: Text(
                    faixa['caminho'] ?? 'Arquivo de áudio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.more_vert),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historico() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Histórico de comandos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (historicoComandos.isEmpty)
              const Text('Nenhum comando executado ainda.'),
            if (historicoComandos.isNotEmpty)
              ...historicoComandos
                  .take(6)
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
