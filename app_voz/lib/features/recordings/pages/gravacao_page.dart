import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/ui/app_spacing.dart';
import '../../../models/gravacao.dart';
import '../../../models/usuario.dart';
import '../../../repositories/gravacao_repository.dart';

class GravacaoPage extends StatefulWidget {
  final Usuario usuario;

  const GravacaoPage({super.key, required this.usuario});

  @override
  State<GravacaoPage> createState() => _GravacaoPageState();
}

class _GravacaoPageState extends State<GravacaoPage> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  StreamSubscription? _recorderSubscription;
  Timer? _duracaoTimer;

  bool _recorderAberto = false;
  bool _playerAberto = false;
  bool _gravando = false;
  bool _pausado = false;
  bool _tocando = false;
  bool _salvandoBanco = false;

  bool _pararPorSilencio = true;
  bool _pararPorPico = false;

  double _decibeis = -160.0;
  double _maiorPico = -160.0;

  int _duracaoSegundos = 0;
  int _tempoSilencioMs = 0;

  final int _intervaloMonitoramentoMs = 300;
  final int _limiteSilencioMs = 5000;
  final double _limiteSilencioDb = -50.0;
  final double _limitePicoDb = -8.0;

  String _status = 'Pronto para gravar.';
  String? _caminhoArquivo;
  String? _motivoParada;

  @override
  void initState() {
    super.initState();
    _inicializarFlutterSound();
  }

  Future<void> _inicializarFlutterSound() async {
    final permissao = await Permission.microphone.request();

    if (!permissao.isGranted) {
      setState(() {
        _status = 'Permissão de microfone negada.';
      });
      return;
    }

    try {
      await _recorder.openRecorder();
      await _player.openPlayer();

      await _recorder.setSubscriptionDuration(
        Duration(milliseconds: _intervaloMonitoramentoMs),
      );

      _recorderSubscription = _recorder.onProgress?.listen((event) {
        if (!mounted) {
          return;
        }

        final decibeisAtuais = event.decibels ?? -160.0;

        setState(() {
          _decibeis = decibeisAtuais;

          if (decibeisAtuais > _maiorPico) {
            _maiorPico = decibeisAtuais;
          }
        });

        _analisarAudioDuranteGravacao(decibeisAtuais);
      });

      setState(() {
        _recorderAberto = true;
        _playerAberto = true;
        _status = 'Flutter Sound inicializado.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao inicializar Flutter Sound: $e';
      });
    }
  }

  void _analisarAudioDuranteGravacao(double decibeisAtuais) {
    if (!_gravando || _pausado) {
      return;
    }

    if (_pararPorSilencio) {
      if (decibeisAtuais <= _limiteSilencioDb) {
        _tempoSilencioMs += _intervaloMonitoramentoMs;
      } else {
        _tempoSilencioMs = 0;
      }

      if (_tempoSilencioMs >= _limiteSilencioMs) {
        pararGravacao(motivo: 'silêncio prolongado');
        return;
      }
    }

    if (_pararPorPico && decibeisAtuais >= _limitePicoDb) {
      pararGravacao(motivo: 'pico forte de volume');
    }
  }

  Future<String> _gerarCaminhoArquivo() async {
    final diretorio = await getApplicationDocumentsDirectory();
    final pasta = Directory('${diretorio.path}/gravacoes');

    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${pasta.path}/gravacao_$timestamp.m4a';
  }

  Future<void> iniciarGravacao() async {
    if (!_recorderAberto) {
      setState(() {
        _status = 'Recorder ainda não está pronto.';
      });
      return;
    }

    if (_gravando) {
      setState(() {
        _status = 'Já está gravando.';
      });
      return;
    }

    if (_tocando) {
      await pararAudio();
    }

    try {
      final caminho = await _gerarCaminhoArquivo();

      await _recorder.startRecorder(
        toFile: caminho,
        codec: Codec.aacMP4,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      );

      _iniciarContadorDuracao();

      setState(() {
        _gravando = true;
        _pausado = false;
        _caminhoArquivo = caminho;
        _motivoParada = null;
        _decibeis = -160.0;
        _maiorPico = -160.0;
        _tempoSilencioMs = 0;
        _duracaoSegundos = 0;
        _status = 'Gravando e analisando áudio em tempo real...';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao iniciar gravação: $e';
      });
    }
  }

  Future<void> pausarGravacao() async {
    if (!_gravando || _pausado) {
      return;
    }

    try {
      await _recorder.pauseRecorder();
      _pararContadorDuracao();

      setState(() {
        _pausado = true;
        _tempoSilencioMs = 0;
        _status = 'Gravação pausada.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao pausar: $e';
      });
    }
  }

  Future<void> retomarGravacao() async {
    if (!_gravando || !_pausado) {
      return;
    }

    try {
      await _recorder.resumeRecorder();
      _iniciarContadorDuracao();

      setState(() {
        _pausado = false;
        _tempoSilencioMs = 0;
        _status = 'Gravação retomada.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao retomar: $e';
      });
    }
  }

  Future<void> pararGravacao({String motivo = 'botão manual'}) async {
    if (!_gravando || _salvandoBanco) {
      return;
    }

    try {
      _pararContadorDuracao();

      final caminhoFinal = await _recorder.stopRecorder();
      final caminhoSalvo = caminhoFinal ?? _caminhoArquivo;

      setState(() {
        _gravando = false;
        _pausado = false;
        _caminhoArquivo = caminhoSalvo;
        _motivoParada = motivo;
        _tempoSilencioMs = 0;
        _salvandoBanco = true;
        _status = 'Salvando gravação...';
      });

      await _salvarGravacaoNoBanco(motivo: motivo);

      if (!mounted) {
        return;
      }

      setState(() {
        _salvandoBanco = false;
        _status = 'Gravação salva. Motivo da parada: $motivo.';
      });
    } catch (e) {
      setState(() {
        _salvandoBanco = false;
        _status = 'Erro ao parar gravação: $e';
      });
    }
  }

  Future<void> _salvarGravacaoNoBanco({required String motivo}) async {
    final usuarioId = widget.usuario.id;
    final caminho = _caminhoArquivo;

    if (usuarioId == null || caminho == null) {
      return;
    }

    final nome = 'Gravação ${DateTime.now().millisecondsSinceEpoch}';

    final gravacao = Gravacao(
      usuarioId: usuarioId,
      nome: nome,
      caminhoArquivo: caminho,
      dataCriacao: DateTime.now().toIso8601String(),
      duracaoSegundos: _duracaoSegundos,
      motivoParada: motivo,
      maiorPico: _maiorPico,
    );

    await GravacaoRepository.instance.criarGravacao(gravacao);
  }

  Future<void> tocarAudio() async {
    if (!_playerAberto) {
      setState(() {
        _status = 'Player ainda não está pronto.';
      });
      return;
    }

    if (_caminhoArquivo == null) {
      setState(() {
        _status = 'Nenhum áudio gravado para tocar.';
      });
      return;
    }

    if (_gravando) {
      setState(() {
        _status = 'Pare a gravação antes de tocar o áudio.';
      });
      return;
    }

    final arquivo = File(_caminhoArquivo!);

    if (!await arquivo.exists()) {
      setState(() {
        _status = 'Arquivo de áudio não encontrado.';
      });
      return;
    }

    if (_tocando) {
      return;
    }

    try {
      await _player.startPlayer(
        fromURI: _caminhoArquivo,
        codec: Codec.aacMP4,
        whenFinished: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _tocando = false;
            _status = 'Reprodução finalizada.';
          });
        },
      );

      setState(() {
        _tocando = true;
        _status = 'Reproduzindo áudio gravado...';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao reproduzir áudio: $e';
      });
    }
  }

  Future<void> pararAudio() async {
    if (!_tocando) {
      return;
    }

    try {
      await _player.stopPlayer();

      setState(() {
        _tocando = false;
        _status = 'Reprodução parada.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao parar reprodução: $e';
      });
    }
  }

  void _iniciarContadorDuracao() {
    _duracaoTimer?.cancel();

    _duracaoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_gravando || _pausado) {
        return;
      }

      setState(() {
        _duracaoSegundos++;
      });
    });
  }

  void _pararContadorDuracao() {
    _duracaoTimer?.cancel();
    _duracaoTimer = null;
  }

  String _formatarDuracao(int segundos) {
    final minutos = segundos ~/ 60;
    final restoSegundos = segundos % 60;
    final min = minutos.toString().padLeft(2, '0');
    final sec = restoSegundos.toString().padLeft(2, '0');
    return '$min:$sec';
  }

  double get _progressoDecibeis {
    return ((_decibeis + 80) / 80).clamp(0.0, 1.0);
  }

  double get _progressoSilencio {
    return (_tempoSilencioMs / _limiteSilencioMs).clamp(0.0, 1.0);
  }

  int get _segundosSilencioRestantes {
    final restanteMs = _limiteSilencioMs - _tempoSilencioMs;
    final restante = (restanteMs / 1000).ceil();
    return restante < 0 ? 0 : restante;
  }

  @override
  void dispose() {
    _duracaoTimer?.cancel();
    _recorderSubscription?.cancel();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  Color get corStatus {
    if (_gravando && !_pausado) {
      return Colors.red;
    }

    if (_pausado) {
      return Colors.orange;
    }

    if (_tocando) {
      return Colors.green;
    }

    return Colors.deepPurple;
  }

  String get textoEstado {
    if (_gravando && !_pausado) {
      return 'Gravando';
    }

    if (_pausado) {
      return 'Pausado';
    }

    if (_tocando) {
      return 'Reproduzindo';
    }

    return 'Pronto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gravação'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardStatus(),
            const SizedBox(height: AppSpacing.lg),
            _cardAnaliseAudio(),
            const SizedBox(height: AppSpacing.lg),
            _cardControles(),
            const SizedBox(height: AppSpacing.lg),
            _cardConfiguracoes(),
            const SizedBox(height: AppSpacing.lg),
            _cardArquivo(),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Esta tela grava áudio, analisa volume em tempo real, para automaticamente por silêncio ou pico e salva a gravação no banco local.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.graphic_eq, size: 64, color: corStatus),
            const SizedBox(height: AppSpacing.sm),
            Text(
              textoEstado,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: corStatus,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatarDuracao(_duracaoSegundos),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (_motivoParada != null) ...[
              const SizedBox(height: 8),
              Text(
                'Última parada: $_motivoParada',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardAnaliseAudio() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Text(
              'Análise em tempo real',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${_decibeis.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progressoDecibeis,
              minHeight: 10,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Maior pico: ${_maiorPico.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_pararPorSilencio && _gravando && !_pausado) ...[
              Text(
                _tempoSilencioMs > 0
                    ? 'Silêncio detectado. Parando em $_segundosSilencioRestantes s...'
                    : 'Aguardando silêncio prolongado...',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progressoSilencio,
                minHeight: 8,
                borderRadius: BorderRadius.circular(20),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardControles() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _gravando || _salvandoBanco ? null : iniciarGravacao,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Gravar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: _gravando && !_pausado ? pausarGravacao : null,
              icon: const Icon(Icons.pause),
              label: const Text('Pausar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: _gravando && _pausado ? retomarGravacao : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Retomar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: _gravando
                  ? () => pararGravacao(motivo: 'botão manual')
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('Parar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: !_gravando && _caminhoArquivo != null && !_tocando
                  ? tocarAudio
                  : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('Tocar'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: _tocando ? pararAudio : null,
              icon: const Icon(Icons.stop_circle),
              label: const Text('Parar áudio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardConfiguracoes() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Text(
              'Reações automáticas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Parar por silêncio'),
              subtitle: Text(
                'Para após ${_limiteSilencioMs ~/ 1000}s abaixo de $_limiteSilencioDb dB.',
              ),
              value: _pararPorSilencio,
              onChanged: _gravando
                  ? null
                  : (value) {
                      setState(() {
                        _pararPorSilencio = value;
                        _tempoSilencioMs = 0;
                      });
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Parar por pico forte'),
              subtitle: Text('Para se o áudio passar de $_limitePicoDb dB.'),
              value: _pararPorPico,
              onChanged: _gravando
                  ? null
                  : (value) {
                      setState(() {
                        _pararPorPico = value;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardArquivo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          _caminhoArquivo == null
              ? 'Nenhum arquivo salvo ainda.'
              : 'Arquivo salvo em:\n$_caminhoArquivo',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
