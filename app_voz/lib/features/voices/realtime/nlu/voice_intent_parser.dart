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

  VoiceIntent parse(String text) {
    final normalized = _normalize(text);

    final confirmation = _matchConfirmation(text, normalized);
    if (confirmation != null) {
      return confirmation;
    }

    final metronome = _matchMetronome(text, normalized);
    if (metronome != null) {
      return metronome;
    }

    final playback = _matchPlayback(text, normalized);
    if (playback != null) {
      return playback;
    }

    final recordingManagement = _matchRecordingManagement(text, normalized);
    if (recordingManagement != null) {
      return recordingManagement;
    }

    final track = _matchTrack(text, normalized);
    if (track != null) {
      return track;
    }

    return UnknownIntent(text);
  }

  static String _normalize(String text) {
    var normalized = text.toLowerCase();
    for (final entry in _accentMap.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
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
    if (RegExp(
      r'(?:para(?:r)? a musica|parar musica|stop|interromper)',
    ).hasMatch(text)) {
      return PlaybackIntent(action: 'stop', rawText: rawText);
    }
    if (RegExp(r'(?:pausar|pausa a musica|pause)').hasMatch(text)) {
      return PlaybackIntent(action: 'pause', rawText: rawText);
    }
    if (RegExp(
      r'(?:tocar|da o play|iniciar|solta o som|play)',
    ).hasMatch(text)) {
      return PlaybackIntent(action: 'start', rawText: rawText);
    }
    return null;
  }

  static VoiceIntent? _matchConfirmation(String rawText, String text) {
    final trimmed = text.trim();
    if (RegExp(
      r'^(?:confirmar|sim|pode|pode\s+apagar|confirma)$',
    ).hasMatch(trimmed)) {
      return ConfirmIntent(rawText: rawText);
    }
    if (RegExp(
      '^(?:cancelar|nao|n\u00e3o|nÃ£o|esquece|cancela)\$',
    ).hasMatch(trimmed)) {
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

    if (RegExp(
      r'(?:deletar|apagar|excluir|remover)\s+(?:ultima\s+)?(?:gravacao|audio|faixa)',
    ).hasMatch(text)) {
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
      r'(?:deletar|delete|apagar|excluir)(?: .{0,24})?(?:faixa|track|canal)?',
    ).hasMatch(text)) {
      return TrackIntent(action: 'delete', rawText: rawText);
    }
    return null;
  }

  static bool _isValidBpm(int? bpm) {
    return bpm != null && bpm >= 40 && bpm <= 300;
  }
}
