class UserFacingMessages {
  const UserFacingMessages._();

  static const genericActionError =
      'Nao foi possivel concluir a acao. Tente novamente.';
  static const commandExecutionError =
      'Nao consegui executar esse comando. Tente novamente.';
  static const deviceActionError =
      'Nao foi possivel concluir a acao neste dispositivo.';
  static const dataLoadError = 'Nao foi possivel carregar os dados.';
  static const dataSaveError =
      'Nao foi possivel salvar as informacoes. Tente novamente.';
  static const playbackError =
      'Nao foi possivel reproduzir o audio. Tente novamente.';
  static const recordingControlError =
      'Nao foi possivel controlar a gravacao agora.';
  static const recordingSaveError =
      'Nao foi possivel salvar a gravacao. Tente novamente.';

  static String voiceStatus(String message) {
    final normalized = _normalize(message);
    return switch (normalized) {
      'sleeping' => 'Aguardando comando',
      'listeningcommand' => 'Ouvindo comando',
      'listening' => 'Ouvindo comando',
      'processingcommand' => 'Processando comando',
      'processing' => 'Processando comando',
      'idle' => 'Pronto para ouvir',
      'active' => 'Controle por voz ativo',
      'inactive' => 'Controle por voz pausado',
      'error' => 'Nao consegui concluir a acao',
      _ => message,
    };
  }

  static String error(Object error, {String fallback = genericActionError}) {
    final publicMessage = _publicExceptionMessage(error);
    if (publicMessage != null && !_looksTechnical(publicMessage)) {
      return publicMessage;
    }

    final text = error.toString();
    if (_looksTechnical(text)) {
      return fallback;
    }

    final cleaned = _stripCommonPrefixes(text);
    return cleaned.isEmpty || _looksTechnical(cleaned) ? fallback : cleaned;
  }

  static String fileName(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return 'arquivo de audio';
    }

    final index = normalized.lastIndexOf('/');
    if (index < 0 || index == normalized.length - 1) {
      return normalized;
    }

    return normalized.substring(index + 1);
  }

  static String currentRecordingFile(String path) {
    return 'Arquivo atual: ${fileName(path)}';
  }

  static String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  static String? _publicExceptionMessage(Object error) {
    if (error is ArgumentError) {
      final message = error.message;
      return message?.toString();
    }

    if (error is StateError) {
      return error.message;
    }

    return null;
  }

  static String _stripCommonPrefixes(String text) {
    return text
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Invalid argument\(s\):\s*'), '')
        .trim();
  }

  static bool _looksTechnical(String text) {
    final lower = text.toLowerCase();
    return lower.contains('gemini_api_key') ||
        lower.contains('platformexception') ||
        lower.contains('exception:') ||
        lower.contains('stacktrace') ||
        lower.contains('stack trace') ||
        lower.contains('sqflite') ||
        lower.contains('sqlite') ||
        lower.contains('database') ||
        lower.contains('repository') ||
        lower.contains('service') ||
        lower.contains('authorization') ||
        lower.contains('token') ||
        lower.contains('current_key') ||
        lower.contains('speechrecognizer') ||
        lower.contains('audiofocus') ||
        lower.contains('nlu') ||
        RegExp(r'(^|[a-z]):[\\/]').hasMatch(lower) ||
        lower.contains('/data/user/') ||
        lower.contains('/storage/') ||
        lower.contains('/tmp/');
  }
}
