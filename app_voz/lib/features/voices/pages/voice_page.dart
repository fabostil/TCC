import 'package:flutter/material.dart';

import '../services/speech_service.dart';
import '../services/tts_service.dart';

enum RecordingStatus { idle, recording, paused }

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();

  RecordingStatus _status = RecordingStatus.idle;
  bool _speechEnabled = false;
  bool _listening = false;
  String _lastCommand = 'Toque no botão e diga um comando';
  final List<String> _markers = <String>[];

  @override
  void initState() {
    super.initState();
    _setupVoice();
  }

  Future<void> _setupVoice() async {
    await _ttsService.initialize();
    final enabled = await _speechService.initialize();

    if (!mounted) {
      return;
    }

    setState(() {
      _speechEnabled = enabled;
      _lastCommand = enabled
          ? 'Pronto para comandos de voz'
          : 'Reconhecimento de voz indisponível no dispositivo';
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechEnabled) {
      await _ttsService.speak('Reconhecimento de voz não está disponível.');
      return;
    }

    if (_listening) {
      await _speechService.stopListening();
      setState(() => _listening = false);
      return;
    }

    setState(() => _listening = true);
    await _speechService.startListening(_processCommand);
  }

  Future<void> _processCommand(String command) async {
    if (command.isEmpty) {
      return;
    }

    final normalized = command.toLowerCase();
    setState(() {
      _lastCommand = command;
    });

    if (_containsAny(normalized, <String>['iniciar gravação', 'começar gravação'])) {
      await _startRecording();
      return;
    }

    if (_containsAny(normalized, <String>['pausar gravação', 'pausar'])) {
      await _pauseRecording();
      return;
    }

    if (_containsAny(normalized, <String>['encerrar gravação', 'parar gravação'])) {
      await _stopRecording();
      return;
    }

    if (_containsAny(normalized, <String>['adicionar marcador', 'novo marcador'])) {
      await _addMarker();
      return;
    }

    await _ttsService.speak('Comando não reconhecido.');
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any(text.contains);
  }

  Future<void> _startRecording() async {
    if (_status == RecordingStatus.recording) {
      await _ttsService.speak('A gravação já está em andamento.');
      return;
    }

    setState(() => _status = RecordingStatus.recording);
    await _ttsService.speak('Gravação iniciada.');
  }

  Future<void> _pauseRecording() async {
    if (_status != RecordingStatus.recording) {
      await _ttsService.speak('Não existe gravação ativa para pausar.');
      return;
    }

    setState(() => _status = RecordingStatus.paused);
    await _ttsService.speak('Gravação pausada.');
  }

  Future<void> _stopRecording() async {
    if (_status == RecordingStatus.idle) {
      await _ttsService.speak('Não existe gravação ativa para encerrar.');
      return;
    }

    setState(() => _status = RecordingStatus.idle);
    await _ttsService.speak('Gravação encerrada.');
  }

  Future<void> _addMarker() async {
    if (_status == RecordingStatus.idle) {
      await _ttsService.speak('Inicie uma gravação antes de adicionar marcador.');
      return;
    }

    final marker = 'Marcador ${_markers.length + 1}';
    setState(() {
      _markers.add(marker);
    });

    await _ttsService.speak('$marker registrado.');
  }

  String get _statusLabel {
    switch (_status) {
      case RecordingStatus.idle:
        return 'Sem gravação';
      case RecordingStatus.recording:
        return 'Gravando';
      case RecordingStatus.paused:
        return 'Pausada';
    }
  }

  @override
  void dispose() {
    _speechService.stopListening();
    _ttsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente de Voz para Músicos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleListening,
        icon: Icon(_listening ? Icons.mic_off : Icons.mic),
        label: Text(_listening ? 'Parar escuta' : 'Escutar'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: const Text('Último comando'),
                subtitle: Text(_lastCommand),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.fiber_manual_record),
                title: const Text('Status da sessão'),
                subtitle: Text(_statusLabel),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Marcadores da sessão (${_markers.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _markers.isEmpty
                  ? const Center(child: Text('Nenhum marcador registrado.'))
                  : ListView.builder(
                      itemCount: _markers.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.bookmark),
                        title: Text(_markers[index]),
                      ),
                    ),
            ),
            const Text(
              'Comandos suportados: iniciar gravação, pausar gravação, '
              'encerrar gravação e adicionar marcador.',
            ),
          ],
        ),
      ),
    );
  }
}
