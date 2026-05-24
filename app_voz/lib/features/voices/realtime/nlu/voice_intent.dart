sealed class VoiceIntent {
  const VoiceIntent(this.rawText);

  final String rawText;
}

final class MetronomeIntent extends VoiceIntent {
  const MetronomeIntent({required this.bpm, required String rawText})
    : super(rawText);

  final int bpm;
}

final class PlaybackIntent extends VoiceIntent {
  const PlaybackIntent({required this.action, required String rawText})
    : super(rawText);

  final String action;
}

final class TrackIntent extends VoiceIntent {
  const TrackIntent({required this.action, required String rawText})
    : super(rawText);

  final String action;
}

final class UnknownIntent extends VoiceIntent {
  const UnknownIntent(super.rawText);
}
