import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../voices/services/speech_service.dart';

class EditorPage extends StatefulWidget {
  final Usuario usuario;

  const EditorPage({super.key, required this.usuario});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final SpeechService speech = SpeechService();

  bool ouvindo = false;
  bool gravando = false;
  bool pausado = false;
  bool reproduzindo = false;

  String textoReconhecido = 'Pressione o microfone e fale um comando.';
  String statusProjeto = 'Projeto pronto para gravar.';
  String nomeProjeto = 'Projeto sem nome';

  final List<String> faixas = [];
  final List<String> historicoComandos = [];

  Future<void> alternarMicrofone() async {
    if (!ouvindo) {
      final disponivel = await speech.initialize();

      if (!disponivel) {
        setState(() {
          statusProjeto = 'Reconhecimento de voz indisponível.';
        });
        return;
      }

      setState(() {
        ouvindo = true;
        textoReconhecido = 'Ouvindo...';
      });

      await speech.startListening((resultado) {
        setState(() {
          textoReconhecido = resultado;
        });

        interpretarComando(resultado);
      });
    } else {
      await speech.stopListening();

      setState(() {
        ouvindo = false;
        textoReconhecido = 'Pressione o microfone e fale um comando.';
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

    if (cmd.contains('reproduzir') || cmd.contains('tocar')) {
      reproduzirProjeto(comando);
      return;
    }

    if (cmd.contains('parar reprodução')) {
      pararReproducao(comando);
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

  void iniciarGravacao(String comando) {
    setState(() {
      gravando = true;
      pausado = false;
      reproduzindo = false;
      statusProjeto = 'Gravação iniciada.';
    });

    adicionarHistorico(comandoOriginal: comando, acao: 'Iniciou gravação');
  }

  void pausarGravacao(String comando) {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para pausar.';
      });
      return;
    }

    setState(() {
      pausado = true;
      statusProjeto = 'Gravação pausada.';
    });

    adicionarHistorico(comandoOriginal: comando, acao: 'Pausou gravação');
  }

  void retomarGravacao(String comando) {
    if (!gravando || !pausado) {
      setState(() {
        statusProjeto = 'Não existe gravação pausada para retomar.';
      });
      return;
    }

    setState(() {
      pausado = false;
      statusProjeto = 'Gravação retomada.';
    });

    adicionarHistorico(comandoOriginal: comando, acao: 'Retomou gravação');
  }

  void encerrarGravacao(String comando) {
    if (!gravando) {
      setState(() {
        statusProjeto = 'Não existe gravação em andamento para encerrar.';
      });
      return;
    }

    final numeroFaixa = faixas.length + 1;
    final nomeFaixa = 'Gravação $numeroFaixa';

    setState(() {
      gravando = false;
      pausado = false;
      faixas.add(nomeFaixa);
      statusProjeto = '$nomeFaixa salva no projeto.';
    });

    adicionarHistorico(
      comandoOriginal: comando,
      acao: 'Encerrou gravação e criou $nomeFaixa',
    );
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
      statusProjeto = 'Reprodução iniciada.';
    });

    adicionarHistorico(comandoOriginal: comando, acao: 'Iniciou reprodução');
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
    speech.stopListening();
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
                  onPressed: () => iniciarGravacao('botão gravar'),
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Gravar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => pausarGravacao('botão pausar'),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => retomarGravacao('botão retomar'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => encerrarGravacao('botão parar'),
                  icon: const Icon(Icons.stop),
                  label: const Text('Parar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => reproduzirProjeto('botão reproduzir'),
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
                onPressed: alternarMicrofone,
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
                  title: Text(faixa),
                  subtitle: const Text('Áudio do projeto'),
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
