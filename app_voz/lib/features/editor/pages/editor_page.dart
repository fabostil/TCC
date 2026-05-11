import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../services/audio_player_service.dart';
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
  final AudioPlayerService playerService = AudioPlayerService();

  bool ouvindo = false;
  bool gravando = false;
  bool pausado = false;
  bool reproduzindo = false;
  bool carregandoAudio = false;

  bool modoAssistenteAtivo = true;
  bool reiniciandoEscuta = false;

  Timer? monitorSilencioTimer;
  Timer? reiniciarEscutaTimer;

  String ultimoComandoProcessado = '';
  DateTime? horarioUltimoComando;

  double nivelAudioAtual = -160.0;
  int tempoSilencioMs = 0;

  final int limiteSilencioMs = 7000;
  final int intervaloMonitoramentoMs = 500;
  final double limiteSilencioDb = -55.0;

  bool paradaAutomaticaPorSilencio = true;

  String textoReconhecido = 'Assistente iniciando...';
  String statusProjeto = 'Sessão pronta para capturar ideias.';
  String nomeProjeto = 'Sessão de captura';
  String? caminhoGravacaoAtual;

  final List<Map<String, String>> faixas = [];
  final List<String> historicoComandos = [];

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && modoAssistenteAtivo && !gravando) {
        iniciarEscutaAutomatica();
      }
    });
  }

  Future<void> iniciarEscutaAutomatica() async {
    if (!modoAssistenteAtivo) {
      return;
    }

    if (gravando || carregandoAudio || ouvindo) {
      return;
    }

    setState(() {
      ouvindo = true;
      textoReconhecido = 'Assistente ouvindo...';
      statusProjeto = 'Diga um comando, como "iniciar gravação".';
    });

    await speech.startListening(
      onResult: (resultado) {
        setState(() {
          textoReconhecido = resultado;
          statusProjeto = 'Comando detectado: $resultado';
        });

        processarComandoComControle(resultado);
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }

        if (status == 'listening') {
          setState(() {
            ouvindo = true;
          });
        }

        if (status == 'done' || status == 'notListening') {
          setState(() {
            ouvindo = false;
          });

          agendarReinicioEscuta();
        }
      },
      onError: (error) {
        if (!mounted) {
          return;
        }

        setState(() {
          ouvindo = false;
        });

        if (error == 'error_speech_timeout') {
          setState(() {
            textoReconhecido = 'Aguardando comando...';
            statusProjeto = 'Assistente ativo. Fale um comando quando quiser.';
          });

          agendarReinicioEscuta();
          return;
        }

        setState(() {
          textoReconhecido = 'Erro ao reconhecer fala.';
          statusProjeto = 'Erro no assistente de voz: $error';
        });

        agendarReinicioEscuta();
      },
    );
  }

  void agendarReinicioEscuta() {
    if (!modoAssistenteAtivo) {
      return;
    }

    if (gravando || carregandoAudio) {
      return;
    }

    if (reiniciandoEscuta) {
      return;
    }

    reiniciandoEscuta = true;

    reiniciarEscutaTimer?.cancel();

    reiniciarEscutaTimer = Timer(const Duration(milliseconds: 800), () {
      reiniciandoEscuta = false;

      if (mounted && modoAssistenteAtivo && !gravando && !carregandoAudio) {
        iniciarEscutaAutomatica();
      }
    });
  }

  Future<void> pararEscutaAutomatica() async {
    reiniciarEscutaTimer?.cancel();
    reiniciandoEscuta = false;

    if (ouvindo) {
      await speech.stopListening();
    }

    if (mounted) {
      setState(() {
        ouvindo = false;
        textoReconhecido = 'Assistente pausado.';
        statusProjeto = 'Escuta automática desativada.';
      });
    }
  }

  void processarComandoComControle(String comando) {
    final comandoLimpo = comando.toLowerCase().trim();

    if (comandoLimpo.isEmpty) {
      return;
    }

    final agora = DateTime.now();

    if (ultimoComandoProcessado == comandoLimpo &&
        horarioUltimoComando != null &&
        agora.difference(horarioUltimoComando!).inSeconds < 3) {
      return;
    }

    ultimoComandoProcessado = comandoLimpo;
    horarioUltimoComando = agora;

    interpretarComando(comando);
  }

  Future<void> alternarModoAssistente() async {
    if (modoAssistenteAtivo) {
      setState(() {
        modoAssistenteAtivo = false;
      });

      await pararEscutaAutomatica();
    } else {
      setState(() {
        modoAssistenteAtivo = true;
        statusProjeto = 'Assistente automático ativado.';
      });

      await iniciarEscutaAutomatica();
    }
  }

  Future<void> alternarMicrofone() async {
    await alternarModoAssistente();
  }

  void interpretarComando(String comando) {
    final cmd = comando.toLowerCase().trim();

    if (cmd.isEmpty) {
      return;
    }

    if (cmd.contains('iniciar gravação') ||
        cmd.contains('começar gravação') ||
        cmd == 'gravar' ||
        cmd.contains('gravar ideia') ||
        cmd.contains('nova gravação')) {
      iniciarGravacao(comando);
      return;
    }

    if (cmd.startsWith('nomear como') ||
        cmd.startsWith('renomear como') ||
        cmd.contains('nomear última') ||
        cmd.contains('nomear ultima') ||
        cmd.contains('renomear última') ||
        cmd.contains('renomear ultima')) {
      renomearUltimaGravacao(comando);
      return;
    }

    if (cmd.contains('tocar última') ||
        cmd.contains('tocar ultima') ||
        cmd.contains('reproduzir última') ||
        cmd.contains('reproduzir ultima') ||
        cmd.contains('tocar gravação') ||
        cmd.contains('reproduzir gravação') ||
        cmd == 'reproduzir' ||
        cmd == 'tocar') {
      reproduzirProjeto(comando);
      return;
    }

    if (cmd.contains('parar reprodução') ||
        cmd.contains('parar áudio') ||
        cmd.contains('parar audio')) {
      pararReproducao(comando);
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

    if (cmd.contains('criar marcador') || cmd.contains('marcar')) {
      criarMarcador(comando);
      return;
    }

    if (cmd.contains('listar gravações') ||
        cmd.contains('mostrar gravações') ||
        cmd.contains('minhas gravações')) {
      listarGravacoes(comando);
      return;
    }

    if (cmd.contains('abrir dashboard') || cmd.contains('dashboard')) {
      abrirDashboardEmBreve(comando);
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

    reiniciarEscutaTimer?.cancel();
    reiniciandoEscuta = false;

    if (ouvindo) {
      await speech.stopListening();

      setState(() {
        ouvindo = false;
      });
    }

    if (reproduzindo) {
      await playerService.stop();

      setState(() {
        reproduzindo = false;
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

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
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

        if (modoAssistenteAtivo) {
          agendarReinicioEscuta();
        }

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
            : '$nomeFaixa salva na sessão.';
      });

      adicionarHistorico(
        comandoOriginal: comando,
        acao: foiParadaAutomatica
            ? 'Encerrou gravação por silêncio'
            : 'Encerrou gravação real e criou $nomeFaixa',
      );

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
    } catch (e) {
      setState(() {
        gravando = false;
        pausado = false;
        carregandoAudio = false;
        statusProjeto = 'Erro ao encerrar gravação: $e';
      });

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
    }
  }

  void renomearUltimaGravacao(String comando) {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Ainda não há gravações para renomear.';
      });
      return;
    }

    String novoNome = comando.toLowerCase().trim();

    novoNome = novoNome
        .replaceAll('nomear última gravação como', '')
        .replaceAll('nomear ultima gravação como', '')
        .replaceAll('renomear última gravação como', '')
        .replaceAll('renomear ultima gravação como', '')
        .replaceAll('nomear última como', '')
        .replaceAll('nomear ultima como', '')
        .replaceAll('renomear última como', '')
        .replaceAll('renomear ultima como', '')
        .replaceAll('nomear como', '')
        .replaceAll('renomear como', '')
        .trim();

    if (novoNome.isEmpty) {
      setState(() {
        statusProjeto = 'Não entendi o novo nome da gravação.';
      });
      return;
    }

    novoNome = _capitalizarTexto(novoNome);

    setState(() {
      faixas[faixas.length - 1]['nome'] = novoNome;
      statusProjeto = 'Última gravação renomeada para "$novoNome".';
      textoReconhecido = comando;
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Renomeou última gravação para $novoNome',
    );
  }

  String _capitalizarTexto(String texto) {
    if (texto.isEmpty) {
      return texto;
    }

    return texto[0].toUpperCase() + texto.substring(1);
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

  Future<void> reproduzirProjeto(String comando) async {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Ainda não há gravações para reproduzir.';
      });
      return;
    }

    final ultimaFaixa = faixas.last;
    await reproduzirFaixa(ultimaFaixa, comandoOriginal: comando);
  }

  Future<void> reproduzirFaixa(
    Map<String, String> faixa, {
    String comandoOriginal = 'botão play da faixa',
  }) async {
    final caminho = faixa['caminho'];
    final nome = faixa['nome'] ?? 'Gravação';

    if (caminho == null || caminho.isEmpty) {
      setState(() {
        statusProjeto = 'Arquivo da gravação não encontrado.';
      });
      return;
    }

    if (gravando) {
      setState(() {
        statusProjeto = 'Pare a gravação antes de reproduzir áudio.';
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
      statusProjeto = 'Preparando reprodução...';
    });

    try {
      await playerService.play(caminho);

      setState(() {
        reproduzindo = true;
        carregandoAudio = false;
        statusProjeto = 'Reproduzindo $nome.';
      });

      adicionarHistorico(
        comandoOriginal: comandoOriginal,
        acao: 'Reproduziu $nome',
      );

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
    } catch (e) {
      setState(() {
        reproduzindo = false;
        carregandoAudio = false;
        statusProjeto = 'Erro ao reproduzir áudio: $e';
      });

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
    }
  }

  Future<void> pararReproducao(String comando) async {
    try {
      await playerService.stop();

      setState(() {
        reproduzindo = false;
        statusProjeto = 'Reprodução parada.';
      });

      adicionarHistorico(comandoOriginal: comando, acao: 'Parou reprodução');

      if (modoAssistenteAtivo) {
        agendarReinicioEscuta();
      }
    } catch (e) {
      setState(() {
        statusProjeto = 'Erro ao parar reprodução: $e';
      });
    }
  }

  void listarGravacoes(String comando) {
    if (faixas.isEmpty) {
      setState(() {
        statusProjeto = 'Nenhuma gravação salva nesta sessão.';
      });
    } else {
      setState(() {
        statusProjeto = 'Você tem ${faixas.length} gravação(ões) nesta sessão.';
      });
    }

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Listou gravações da sessão',
    );
  }

  void abrirDashboardEmBreve(String comando) {
    setState(() {
      statusProjeto = 'Dashboard será implementado em breve.';
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Tentou abrir dashboard',
    );
  }

  void criarMarcador(String comando) {
    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Criou marcador na sessão',
    );

    setState(() {
      statusProjeto = 'Marcador criado no ponto atual.';
    });
  }

  void limparTexto(String comando) {
    setState(() {
      textoReconhecido = 'Assistente ouvindo...';
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

    if (ouvindo) {
      return Colors.blue;
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

    if (ouvindo) {
      return 'Ouvindo';
    }

    return 'Pronto';
  }

  @override
  void dispose() {
    reiniciarEscutaTimer?.cancel();
    pararMonitoramentoSilencio();
    speech.stopListening();
    audioService.dispose();
    playerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessão de Captura'), centerTitle: true),
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
              subtitle: const Text('Encerra após 7 segundos em silêncio.'),
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
              'Captura atual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Início'),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: gravando || reproduzindo ? 0.45 : 0.0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Ideia'),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Área simplificada para acompanhar a captura da ideia musical.',
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
              'Controles manuais',
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
                  label: const Text('Tocar última'),
                ),
                OutlinedButton.icon(
                  onPressed: carregandoAudio
                      ? null
                      : () => pararReproducao('botão parar reprodução'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Parar áudio'),
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
              'O assistente fica ouvindo automaticamente quando não há gravação em andamento. Comandos: iniciar gravação, tocar última gravação, nomear como refrão, listar gravações.',
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
                backgroundColor: modoAssistenteAtivo
                    ? Colors.deepPurple
                    : Colors.grey,
                icon: Icon(
                  modoAssistenteAtivo ? Icons.hearing : Icons.hearing_disabled,
                ),
                label: Text(
                  modoAssistenteAtivo
                      ? 'Assistente ativo'
                      : 'Ativar assistente',
                ),
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
              'Ideias capturadas',
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
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: carregandoAudio
                        ? null
                        : () {
                            reproduzirFaixa(faixa);
                          },
                  ),
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
