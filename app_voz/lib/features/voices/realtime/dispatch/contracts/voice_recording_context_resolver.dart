import '../../../../../models/gravacao.dart';

abstract class VoiceRecordingContextResolver {
  Future<Gravacao?> resolveLastRecording();
}

class StubVoiceRecordingContextResolver
    implements VoiceRecordingContextResolver {
  const StubVoiceRecordingContextResolver();

  @override
  Future<Gravacao?> resolveLastRecording() async => null;
}
