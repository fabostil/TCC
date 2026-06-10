import 'dart:io';
import 'dart:typed_data';

import 'package:app_voz/features/editor/services/audio_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  group('AudioRecordingService', () {
    late Directory tempDir;
    late _FakeAudioRecorderClient recorder;
    late _FakeAudioRecordingSessionClient session;
    late AudioRecordingService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_recording_service_test_',
      );
      recorder = _FakeAudioRecorderClient();
      session = _FakeAudioRecordingSessionClient();
      service = AudioRecordingService.test(
        recorder: recorder,
        sessionClient: session,
        documentsDirectoryProvider: () async => tempDir,
      );
    });

    tearDown(() async {
      await service.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('startRecording inicia recorder com permissao e path m4a', () async {
      final path = await service.startRecording();
      final normalizedPath = _normalizePath(path);
      final normalizedTempPath = _normalizePath(tempDir.path);

      expect(normalizedPath, startsWith('$normalizedTempPath/gravacoes/'));
      expect(normalizedPath, contains('/gravacoes/gravacao_'));
      expect(normalizedPath, endsWith('.m4a'));
      expect(recorder.hasPermissionCalls, 1);
      expect(recorder.startCalls, 1);
      expect(recorder.lastStartPath, path);
      expect(recorder.lastConfig?.encoder, AudioEncoder.aacLc);
      expect(recorder.lastConfig?.bitRate, 128000);
      expect(recorder.lastConfig?.sampleRate, 44100);
      expect(session.calls, ['enter:audio_recorder_start']);
      expect(await Directory('${tempDir.path}/gravacoes').exists(), isTrue);
    });

    test(
      'startRecording sem permissao nao chama start e libera sessao',
      () async {
        recorder.permission = false;

        await expectLater(
          service.startRecording(),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Permissao de microfone negada.'),
            ),
          ),
        );
        expect(recorder.startCalls, 0);
        expect(session.calls, [
          'enter:audio_recorder_start',
          'exit:record_permission_denied',
        ]);
      },
    );

    test(
      'startRecording registra falha, libera sessao e propaga erro',
      () async {
        final error = StateError('start failed');
        recorder.startError = error;

        await expectLater(service.startRecording(), throwsA(same(error)));
        expect(session.startFailures, hasLength(1));
        expect(
          session.startFailures.single.reason,
          'audio_recording_start_failed',
        );
        expect(session.calls, [
          'enter:audio_recorder_start',
          'failure:audio_recording_start_failed',
          'exit:record_start_failed',
        ]);
      },
    );

    test(
      'stopRecording retorna path valido do recorder e libera sessao',
      () async {
        recorder.stopResult = '${tempDir.path}/final.m4a';

        final path = await service.stopRecording();

        expect(path, '${tempDir.path}/final.m4a');
        expect(recorder.stopCalls, 1);
        expect(session.calls, ['exit:audio_recorder_stop']);
      },
    );

    test(
      'stopRecording usa path atual quando recorder retorna null ou vazio',
      () async {
        final startedPath = await service.startRecording();
        session.calls.clear();

        recorder.stopResult = null;
        expect(await service.stopRecording(), startedPath);
        expect(session.calls, ['exit:audio_recorder_stop']);

        session.calls.clear();
        recorder.stopResult = '';
        expect(await service.stopRecording(), startedPath);
        expect(session.calls, ['exit:audio_recorder_stop']);
      },
    );

    test(
      'stopRecording sem path atual retorna null quando recorder retorna null',
      () async {
        recorder.stopResult = null;

        final path = await service.stopRecording();

        expect(path, isNull);
        expect(session.calls, ['exit:audio_recorder_stop']);
      },
    );

    test('stopRecording propaga erro do recorder sem mascarar', () async {
      final error = StateError('stop failed');
      recorder.stopError = error;

      await expectLater(service.stopRecording(), throwsA(same(error)));
    });

    test('pauseRecording so pausa quando recorder esta gravando', () async {
      recorder.recording = true;

      await service.pauseRecording();

      expect(recorder.pauseCalls, 1);
      expect(session.calls, ['pause:record_pause', 'paused:record_pause']);

      session.calls.clear();
      recorder.recording = false;
      await service.pauseRecording();

      expect(recorder.pauseCalls, 1);
      expect(session.calls, isEmpty);
    });

    test('resumeRecording so retoma quando recorder esta pausado', () async {
      recorder.paused = true;

      await service.resumeRecording();

      expect(recorder.resumeCalls, 1);
      expect(session.calls, [
        'recording:record_resume',
        'resumed:record_resume',
      ]);

      session.calls.clear();
      recorder.paused = false;
      await service.resumeRecording();

      expect(recorder.resumeCalls, 1);
      expect(session.calls, isEmpty);
    });

    test(
      'cancelRecording cancela recorder, limpa path e libera sessao',
      () async {
        await service.startRecording();
        session.calls.clear();

        await service.cancelRecording();
        recorder.stopResult = null;
        final path = await service.stopRecording();

        expect(path, isNull);
        expect(recorder.cancelCalls, 1);
        expect(session.calls, [
          'exit:audio_recorder_cancel',
          'exit:audio_recorder_stop',
        ]);
      },
    );

    test('dispose fecha stream, libera sessao e e idempotente', () async {
      final chunks = <Uint8List>[];
      var done = false;
      service.rawAudioChunks.listen(chunks.add, onDone: () => done = true);
      service.publishRawAudioChunkForTesting(Uint8List.fromList([1, 2, 3]));

      await service.dispose();
      await service.dispose();

      expect(chunks.single, [1, 2, 3]);
      expect(done, isTrue);
      expect(recorder.disposeCalls, 1);
      expect(session.calls, ['exit:audio_recorder_dispose']);
    });

    test('consultas delegam para recorder', () async {
      recorder.recording = true;
      recorder.paused = true;
      recorder.amplitude = Amplitude(current: -20, max: -10);

      expect(await service.hasPermission(), isTrue);
      expect(await service.isRecording(), isTrue);
      expect(await service.isPaused(), isTrue);
      expect((await service.getAmplitude()).current, -20);
    });
  });
}

class _FakeAudioRecorderClient implements AudioRecorderClient {
  bool permission = true;
  bool recording = false;
  bool paused = false;
  String? stopResult;
  Object? startError;
  Object? stopError;
  Amplitude amplitude = Amplitude(current: -60, max: -12);

  int hasPermissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  RecordConfig? lastConfig;
  String? lastStartPath;

  @override
  Future<bool> hasPermission() async {
    hasPermissionCalls += 1;
    return permission;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls += 1;
    final error = startError;
    if (error != null) {
      throw error;
    }
    lastConfig = config;
    lastStartPath = path;
    recording = true;
    stopResult ??= path;
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    final error = stopError;
    if (error != null) {
      throw error;
    }
    recording = false;
    paused = false;
    return stopResult;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    paused = false;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    recording = false;
    paused = false;
  }

  @override
  Future<Amplitude> getAmplitude() async => amplitude;

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<bool> isPaused() async => paused;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

class _FakeAudioRecordingSessionClient implements AudioRecordingSessionClient {
  final calls = <String>[];
  final startFailures = <_StartFailure>[];

  @override
  void enterRecordingMode({required String ownerId, required String reason}) {
    calls.add('enter:$reason');
  }

  @override
  void exitRecordingMode({required String ownerId, required String reason}) {
    calls.add('exit:$reason');
  }

  @override
  void transitionToPaused({required String ownerId, required String reason}) {
    calls.add('pause:$reason');
  }

  @override
  void transitionToRecording({
    required String ownerId,
    required String reason,
  }) {
    calls.add('recording:$reason');
  }

  @override
  void recordStartFailure({
    required String ownerId,
    required Object error,
    required StackTrace stackTrace,
    required String path,
  }) {
    startFailures.add(_StartFailure(reason: 'audio_recording_start_failed'));
    calls.add('failure:audio_recording_start_failed');
  }

  @override
  void publishPaused({required String ownerId, required String reason}) {
    calls.add('paused:$reason');
  }

  @override
  void publishResumed({required String ownerId, required String reason}) {
    calls.add('resumed:$reason');
  }
}

class _StartFailure {
  const _StartFailure({required this.reason});

  final String reason;
}

String _normalizePath(String value) => value.replaceAll(r'\', '/');
