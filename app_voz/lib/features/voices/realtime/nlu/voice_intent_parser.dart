import 'dart:developer' as developer;

import 'voice_intent.dart';

class VoiceIntentParser {
  const VoiceIntentParser();

  static const Map<String, String> _accentMap = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'è': 'e',
    'ë': 'e',
    'í': 'i',
    'î': 'i',
    'ì': 'i',
    'ï': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ò': 'o',
    'ö': 'o',
    'ú': 'u',
    'û': 'u',
    'ù': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  static const Map<String, int> _scopedBpmWords = {
    'quarenta': 40,
    'cinquenta': 50,
    'sessenta': 60,
    'setenta': 70,
    'oitenta': 80,
    'noventa': 90,
    'cem': 100,
    'cento e dez': 110,
    'cento e vinte': 120,
    'cento e trinta': 130,
    'cento e quarenta': 140,
    'cento e cinquenta': 150,
    'cento e sessenta': 160,
    'cento e setenta': 170,
    'cento e oitenta': 180,
    'cento e noventa': 190,
    'duzentos': 200,
    'trezentos': 300,
  };

  static const Map<String, String> _deleteActionVariants = {
    'apagar': 'apagar',
    'deletar': 'apagar',
    'vagar': 'apagar',
    'pagar': 'apagar',
    'abagar': 'apagar',
    'excluir': 'apagar',
  };

  static const Map<String, String> _confirmActionVariants = {
    'confirmar': 'confirmar',
    'confirma': 'confirmar',
    'sim': 'confirmar',
    'pode': 'confirmar',
    'manda': 'confirmar',
    'mandar': 'confirmar',
    'sin': 'confirmar',
  };

  static const Map<String, String> _cancelActionVariants = {
    'cancelar': 'cancelar',
    'cancela': 'cancelar',
    'nao': 'cancelar',
    'não': 'cancelar',
    'para': 'cancelar',
    'abortar': 'cancelar',
    'sai': 'cancelar',
  };

  static const Map<String, String> _playbackActionVariants = {
    'tocar': 'tocar',
    'toca': 'tocar',
    'play': 'tocar',
    'plei': 'tocar',
    'pausar': 'pausar',
    'pausa': 'pausar',
    'pause': 'pausar',
    'parar': 'parar',
    'stop': 'parar',
    'interromper': 'parar',
  };

  VoiceIntent parse(String text) {
    final normalized = _normalize(text);

    final confirmation = _matchConfirmation(text, normalized);
    if (confirmation != null) {
      return _logMatchedIntent(confirmation);
    }

    final metronome = _matchMetronome(text, normalized);
    if (metronome != null) {
      return _logMatchedIntent(metronome);
    }

    final playback = _matchPlayback(text, normalized);
    if (playback != null) {
      return _logMatchedIntent(playback);
    }

    final recordingManagement = _matchRecordingManagement(text, normalized);
    if (recordingManagement != null) {
      return _logMatchedIntent(recordingManagement);
    }

    final track = _matchTrack(text, normalized);
    if (track != null) {
      return _logMatchedIntent(track);
    }

    return _logMatchedIntent(UnknownIntent(text));
  }

  VoiceIntent _logMatchedIntent(VoiceIntent intent) {
    developer.log(
      '[NLU_DEBUG] TEXTO MATCHEADO PARA INTENT: ${_describeIntent(intent)}',
      name: 'VoiceIntentParser',
    );
    return intent;
  }

  String _describeIntent(VoiceIntent intent) {
    return switch (intent) {
      MetronomeIntent(:final bpm) => 'MetronomeIntent(bpm=$bpm)',
      PlaybackIntent(:final action) => 'PlaybackIntent(action=$action)',
      TrackIntent(:final action) => 'TrackIntent(action=$action)',
      DeleteLastRecordingIntent() => 'DeleteLastRecordingIntent',
      RenameLastRecordingIntent(:final newName) =>
        'RenameLastRecordingIntent(newName=$newName)',
      ConfirmIntent() => 'ConfirmIntent',
      CancelIntent() => 'CancelIntent',
      UnknownIntent(:final rawText) => 'UnknownIntent(rawText=$rawText)',
    };
  }

  static String _normalize(String text) {
    var normalized = text.toLowerCase();
    for (final entry in _accentMap.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  static String _normalizeScopedVariants(
    String text,
    Map<String, String> variants,
  ) {
    var normalized = text;
    for (final entry in variants.entries) {
      normalized = normalized.replaceAllMapped(
        RegExp('(^|\\s)${RegExp.escape(entry.key)}(?=\\s|\$)'),
        (match) => '${match.group(1)}${entry.value}',
      );
    }
    return normalized;
  }

  static VoiceIntent? _matchMetronome(String rawText, String text) {
    final digitPattern = RegExp(
      r'(?:metronomo|bpm|batida).{0,32}?(\d{2,3})|(\d{2,3}).{0,32}?(?:bpm|metronomo|batida)',
    );
    final digitMatch = digitPattern.firstMatch(text);
    final rawBpm = digitMatch?.group(1) ?? digitMatch?.group(2);
    if (rawBpm != null) {
      final bpm = int.tryParse(rawBpm);
      if (_isValidBpm(bpm)) {
        return MetronomeIntent(bpm: bpm!, rawText: rawText);
      }
      return null;
    }

    final bpmWords = _scopedBpmWords.keys.map(RegExp.escape).join('|');
    final wordPattern = RegExp(
      '(?:metronomo|bpm|batida).{0,32}?($bpmWords)|($bpmWords).{0,32}?(?:bpm|metronomo|batida)',
    );
    final wordMatch = wordPattern.firstMatch(text);
    final rawWordBpm = wordMatch?.group(1) ?? wordMatch?.group(2);
    if (rawWordBpm == null) {
      return null;
    }

    final bpm = _scopedBpmWords[rawWordBpm];
    if (_isValidBpm(bpm)) {
      return MetronomeIntent(bpm: bpm!, rawText: rawText);
    }
    return null;
  }

  static VoiceIntent? _matchPlayback(String rawText, String text) {
    final playbackText = _normalizeScopedVariants(
      text,
      _playbackActionVariants,
    );
    if (RegExp(
      r'(?:para(?:r)? a musica|parar musica|parar|stop|interromper)',
    ).hasMatch(playbackText)) {
      return PlaybackIntent(action: 'stop', rawText: rawText);
    }
    if (RegExp(r'(?:pausar|pausa a musica|pause)').hasMatch(playbackText)) {
      return PlaybackIntent(action: 'pause', rawText: rawText);
    }
    if (RegExp(
      r'(?:tocar|da o play|iniciar|solta o som|play)',
    ).hasMatch(playbackText)) {
      return PlaybackIntent(action: 'start', rawText: rawText);
    }
    return null;
  }

  static VoiceIntent? _matchConfirmation(String rawText, String text) {
    final confirmText = _normalizeScopedVariants(text, _confirmActionVariants);
    final cancelText = _normalizeScopedVariants(text, _cancelActionVariants);
    final trimmedConfirm = confirmText.trim();
    final trimmedCancel = cancelText.trim();
    if (RegExp(
      r'^(?:confirmar|confirmar\s+apagar|confirmar\s+confirmar)$',
    ).hasMatch(trimmedConfirm)) {
      return ConfirmIntent(rawText: rawText);
    }
    if (RegExp(
      '^(?:cancelar|nao|não|esquece|cancela)\$',
    ).hasMatch(trimmedCancel)) {
      return CancelIntent(rawText: rawText);
    }
    return null;
  }

  static VoiceIntent? _matchRecordingManagement(String rawText, String text) {
    final renameMatch = RegExp(
      r'(?:renomear|mudar o nome da)\s+(?:ultima\s+)?(?:gravacao|faixa)\s+para\s+(.+)',
    ).firstMatch(text);
    final newName = renameMatch?.group(1)?.trim();
    if (newName != null && newName.isNotEmpty) {
      return RenameLastRecordingIntent(newName: newName, rawText: rawText);
    }

    final deleteText = _normalizeScopedVariants(text, _deleteActionVariants);
    if (RegExp(
      r'(?:apagar|remover)\s+(?:a\s+|o\s+)?(?:ultima\s+)?(?:gravacao|audio|faixa)',
    ).hasMatch(deleteText)) {
      return DeleteLastRecordingIntent(rawText: rawText);
    }

    return null;
  }

  static VoiceIntent? _matchTrack(String rawText, String text) {
    if (RegExp(
      r'(?:gravar|grava|recordar|record)(?: .{0,24})?(?:faixa|track|canal)?',
    ).hasMatch(text)) {
      return TrackIntent(action: 'record', rawText: rawText);
    }
    if (RegExp(
      r'(?:mutar|muta|silenciar|mute)(?: .{0,24})?(?:faixa|track|canal)?',
    ).hasMatch(text)) {
      return TrackIntent(action: 'mute', rawText: rawText);
    }
    if (RegExp(
      r'(?:deletar|delete|apagar|excluir)(?: .{0,24})?(?:faixa|track|canal)',
    ).hasMatch(text)) {
      return TrackIntent(action: 'delete', rawText: rawText);
    }
    return null;
  }

  static bool _isValidBpm(int? bpm) {
    return bpm != null && bpm >= 40 && bpm <= 300;
  }
}
