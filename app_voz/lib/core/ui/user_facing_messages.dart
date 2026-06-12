class UserFacingMessages {
  const UserFacingMessages._();

  static const genericActionError =
      'Não consegui concluir essa ação. Tente novamente.';
  static const commandExecutionError =
      'Não consegui executar esse comando agora. Tente dizer de outro jeito.';
  static const deviceActionError =
      'Não consegui concluir essa ação neste dispositivo.';
  static const dataLoadError =
      'Não consegui carregar as informações agora. Tente novamente.';
  static const dataSaveError =
      'Não consegui salvar as informações agora. Confira os dados e tente novamente.';
  static const playbackError =
      'Não consegui reproduzir esta gravação agora. Verifique se o arquivo está disponível.';
  static const recordingControlError =
      'Não consegui controlar a gravação agora. Verifique o microfone e tente novamente.';
  static const recordingSaveError =
      'Não consegui salvar a gravação agora. Tente encerrar novamente.';

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
      'error' => genericActionError,
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
      return 'arquivo de áudio';
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
