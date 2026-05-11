import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FlutterSoundTestPage extends StatefulWidget {
  const FlutterSoundTestPage({super.key});

  @override
  State<FlutterSoundTestPage> createState() => _FlutterSoundTestPageState();
}

class _FlutterSoundTestPageState extends State<FlutterSoundTestPage> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  StreamSubscription? _recorderSubscription;

  bool _recorderAberto = false;
  bool _gravando = false;
  bool _pausado = false;

  double _decibeis = -160.0;
  String _status = 'Pronto para testar Flutter Sound.';
  String? _caminhoArquivo;

  @override
  void initState() {
    super.initState();
    _inicializarRecorder();
  }

  Future<void> _inicializarRecorder() async {
    final permissao = await Permission.microphone.request();

    if (!permissao.isGranted) {
      setState(() {
        _status = 'Permissão de microfone negada.';
      });
      return;
    }

    try {
      await _recorder.openRecorder();

      await _recorder.setSubscriptionDuration(
        const Duration(milliseconds: 300),
      );

      _recorderSubscription = _recorder.onProgress?.listen((event) {
        if (!mounted) {
          return;
        }

        setState(() {
          _decibeis = event.decibels ?? -160.0;
        });
      });

      setState(() {
        _recorderAberto = true;
        _status = 'Flutter Sound inicializado.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao inicializar recorder: $e';
      });
    }
  }

  Future<String> _gerarCaminhoArquivo() async {
    final diretorio = await getApplicationDocumentsDirectory();

    final pasta = Directory('${diretorio.path}/flutter_sound_test');

    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${pasta.path}/teste_$timestamp.m4a';
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

    try {
      final caminho = await _gerarCaminhoArquivo();

      await _recorder.startRecorder(
        toFile: caminho,
        codec: Codec.aacMP4,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      );

      setState(() {
        _gravando = true;
        _pausado = false;
        _caminhoArquivo = caminho;
        _status = 'Gravando com Flutter Sound...';
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

      setState(() {
        _pausado = true;
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

      setState(() {
        _pausado = false;
        _status = 'Gravação retomada.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao retomar: $e';
      });
    }
  }

  Future<void> pararGravacao() async {
    if (!_gravando) {
      return;
    }

    try {
      final caminhoFinal = await _recorder.stopRecorder();

      setState(() {
        _gravando = false;
        _pausado = false;
        _caminhoArquivo = caminhoFinal ?? _caminhoArquivo;
        _status = 'Gravação salva com Flutter Sound.';
      });
    } catch (e) {
      setState(() {
        _status = 'Erro ao parar gravação: $e';
      });
    }
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _recorder.closeRecorder();
    super.dispose();
  }

  Color get corStatus {
    if (_gravando && !_pausado) {
      return Colors.red;
    }

    if (_pausado) {
      return Colors.orange;
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

    return 'Pronto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste Flutter Sound'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Icon(Icons.graphic_eq, size: 64, color: corStatus),
                    const SizedBox(height: 12),
                    Text(
                      textoEstado,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: corStatus,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '${_decibeis.toStringAsFixed(1)} dB',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: ((_decibeis + 80) / 80).clamp(0.0, 1.0),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _gravando ? null : iniciarGravacao,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('Gravar'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _gravando && !_pausado ? pausarGravacao : null,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pausar'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _gravando && _pausado ? retomarGravacao : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Retomar'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _gravando ? pararGravacao : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Parar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _caminhoArquivo == null
                      ? 'Nenhum arquivo salvo ainda.'
                      : 'Arquivo salvo em:\n$_caminhoArquivo',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Objetivo deste teste: confirmar que o Flutter Sound consegue gravar áudio no celular e mostrar o nível de entrada em tempo real. Depois disso, vamos testar stream único e detecção de comando.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
