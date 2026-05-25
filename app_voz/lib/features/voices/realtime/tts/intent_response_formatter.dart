import '../nlu/voice_intent.dart';

class IntentResponseFormatter {
  const IntentResponseFormatter();

  String format(VoiceIntent intent) {
    return switch (intent) {
      MetronomeIntent(:final bpm) =>
        'Ajustando metronomo para $bpm batidas por minuto',
      PlaybackIntent(:final action) => _playbackResponse(action),
      TrackIntent(:final action) => _trackResponse(action),
      DeleteLastRecordingIntent() =>
        'A última gravação foi excluída com sucesso.',
      RenameLastRecordingIntent(:final newName) =>
        'Faixa renomeada para $newName.',
      ConfirmIntent() => 'Confirmado.',
      CancelIntent() => 'Cancelado.',
      UnknownIntent() => unknownCommandResponse,
    };
  }

  String get unknownCommandResponse =>
      'Desculpe, não consegui entender o comando musical. Você pode tentar dizer tocar, pausar ou mudar o metrônomo.';

  String formatFailure(String reason) {
    return switch (reason) {
      'no_track_selected' =>
        'Nenhuma gravação foi selecionada no editor para reproduzir.',
      'audio_output_unavailable' =>
        'O canal de áudio está ocupado no momento. Tente novamente em instantes.',
      'database_error' =>
        'Não foi possível alterar o arquivo no banco de dados agora.',
      'recording_context_missing' =>
        'Não encontrei uma gravação recente para alterar.',
      _ => 'Nao consegui executar o comando musical agora',
    };
  }

  String formatConfirmation(String action, VoiceIntent intent) {
    if (action == 'delete_last_recording' &&
        intent is DeleteLastRecordingIntent) {
      return 'Confirmar exclusão da última gravação? Diga confirmar ou cancelar.';
    }
    return 'Confirme a acao por voz para continuar.';
  }

  String formatConfirmationResolved(
    String action,
    VoiceIntent intent, {
    required bool approved,
  }) {
    if (!approved && action == 'delete_last_recording') {
      return 'ExclusÃ£o cancelada. A gravaÃ§Ã£o foi mantida.';
    }
    if (approved) {
      return format(intent);
    }
    return 'Acao cancelada.';
  }

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
