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

final class DeleteLastRecordingIntent extends VoiceIntent {
  const DeleteLastRecordingIntent({required String rawText}) : super(rawText);
}

final class RenameLastRecordingIntent extends VoiceIntent {
  const RenameLastRecordingIntent({
    required this.newName,
    required String rawText,
  }) : super(rawText);

  final String newName;
}

final class ConfirmIntent extends VoiceIntent {
  const ConfirmIntent({required String rawText}) : super(rawText);
}

final class CancelIntent extends VoiceIntent {
  const CancelIntent({required String rawText}) : super(rawText);
}

final class UnknownIntent extends VoiceIntent {
  const UnknownIntent(super.rawText);
}
