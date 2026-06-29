import 'dart:io';
import 'dart:typed_data';

import 'package:app_voz/features/voices/realtime/infrastructure/persistence/pcm_wav_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PcmWavFileWriter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pcm_wav_writer_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('escreve header WAV PCM e recalcula tamanhos no fechamento', () async {
      final path = '${tempDir.path}/take.wav';
      final writer = await PcmWavFileWriter.open(path);

      writer.writeChunk(Uint8List.fromList([1, 2, 3, 4]));
      writer.writeChunk(Uint8List.fromList([5, 6]));
      await writer.flushAndClose();

      final bytes = await File(path).readAsBytes();
      final data = ByteData.sublistView(bytes);

      expect(bytes.length, 50);
      expect(_ascii(bytes, 0, 4), 'RIFF');
      expect(data.getUint32(4, Endian.little), 42);
      expect(_ascii(bytes, 8, 4), 'WAVE');
      expect(_ascii(bytes, 12, 4), 'fmt ');
      expect(data.getUint32(16, Endian.little), 16);
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 16000);
      expect(data.getUint32(28, Endian.little), 32000);
      expect(data.getUint16(32, Endian.little), 2);
      expect(data.getUint16(34, Endian.little), 16);
      expect(_ascii(bytes, 36, 4), 'data');
      expect(data.getUint32(40, Endian.little), 6);
      expect(bytes.sublist(44), [1, 2, 3, 4, 5, 6]);
      expect(writer.audioBytesWritten, 6);
      expect(writer.isClosed, isTrue);
    });

    test('respeita sample rate e canais customizados', () async {
      final path = '${tempDir.path}/stereo.wav';
      final writer = await PcmWavFileWriter.open(
        path,
        sampleRate: 44100,
        numChannels: 2,
      );

      writer.writeChunk(Uint8List.fromList([1, 2, 3, 4]));
      await writer.flushAndClose();

      final bytes = await File(path).readAsBytes();
      final data = ByteData.sublistView(bytes);

      expect(data.getUint16(22, Endian.little), 2);
      expect(data.getUint32(24, Endian.little), 44100);
      expect(data.getUint32(28, Endian.little), 176400);
      expect(data.getUint16(32, Endian.little), 4);
      expect(data.getUint32(40, Endian.little), 4);
    });

    test(
      'rejeita escrita apos fechamento e mantem close idempotente',
      () async {
        final path = '${tempDir.path}/closed.wav';
        final writer = await PcmWavFileWriter.open(path);

        await writer.flushAndClose();
        await writer.flushAndClose();

        expect(
          () => writer.writeChunk(Uint8List.fromList([1, 2])),
          throwsStateError,
        );
        expect((await File(path).readAsBytes()).length, 44);
      },
    );

    test('valida parametros basicos de abertura', () async {
      expect(
        () =>
            PcmWavFileWriter.open('${tempDir.path}/invalid.wav', sampleRate: 0),
        throwsArgumentError,
      );
      expect(
        () => PcmWavFileWriter.open(
          '${tempDir.path}/invalid.wav',
          numChannels: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

String _ascii(Uint8List bytes, int offset, int length) {
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}
