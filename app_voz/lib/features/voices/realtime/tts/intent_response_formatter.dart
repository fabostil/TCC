import '../nlu/voice_intent.dart';

class IntentResponseFormatter {
  const IntentResponseFormatter();

  String format(VoiceIntent intent) {
    return switch (intent) {
      MetronomeIntent(:final bpm) =>
        'Ajustando metronomo para $bpm batidas por minuto',
      PlaybackIntent(:final action) => _playbackResponse(action),
      TrackIntent(:final action) => _trackResponse(action),
      UnknownIntent() => unknownCommandResponse,
    };
  }

  String get unknownCommandResponse =>
      'Desculpe, nao consegui entender o comando musical';

  String _playbackResponse(String action) {
    return switch (action) {
      'start' => 'Iniciando reproducao',
      'stop' => 'Parando a musica',
      'pause' => 'Pausando a musica',
      _ => unknownCommandResponse,
    };
  }

  String _trackResponse(String action) {
    return switch (action) {
      'record' => 'Preparando gravacao da faixa',
      'mute' => 'Silenciando a faixa',
      'delete' => 'Removendo a faixa',
      _ => unknownCommandResponse,
    };
  }
}
