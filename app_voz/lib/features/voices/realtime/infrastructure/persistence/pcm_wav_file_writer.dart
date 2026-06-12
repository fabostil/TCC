import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

class PcmWavFileWriter {
  PcmWavFileWriter._({
    required RandomAccessFile file,
    required this.filePath,
    required this.sampleRate,
    required this.numChannels,
  }) : _file = file,
       _blockAlign = numChannels * _bitsPerSample ~/ 8;

  static const int _bitsPerSample = 16;
  static const int _headerSize = 44;

  final String filePath;
  final int sampleRate;
  final int numChannels;
  final int _blockAlign;
  final RandomAccessFile _file;

  int _audioBytesWritten = 0;
  bool _closed = false;

  int get audioBytesWritten => _audioBytesWritten;
  bool get isClosed => _closed;

  static Future<PcmWavFileWriter> open(
    String filePath, {
    int sampleRate = 16000,
    int numChannels = 1,
  }) async {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'deve ser positivo');
    }
    if (numChannels <= 0) {
      throw ArgumentError.value(
        numChannels,
        'numChannels',
        'deve ser positivo',
      );
    }

    final file = await File(filePath).open(mode: FileMode.write);
    try {
      final writer = PcmWavFileWriter._(
        file: file,
        filePath: filePath,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
      file.writeFromSync(writer._buildHeader(audioBytes: 0));
      return writer;
    } catch (error, stackTrace) {
      developer.log(
        'pcm_wav_file_open_failed',
        name: 'PcmWavFileWriter',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        file.closeSync();
      } catch (closeError, closeStackTrace) {
        developer.log(
          'pcm_wav_file_close_after_open_failed',
          name: 'PcmWavFileWriter',
          error: closeError,
          stackTrace: closeStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void writeChunk(Uint8List chunk) {
    if (_closed) {
      throw StateError('PcmWavFileWriter ja foi fechado.');
    }
    if (chunk.isEmpty) {
      return;
    }

    var failed = false;
    try {
      _file.writeFromSync(chunk);
      _audioBytesWritten += chunk.length;
    } catch (error, stackTrace) {
      failed = true;
      developer.log(
        'pcm_wav_file_write_failed',
        name: 'PcmWavFileWriter',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (failed) {
        _closeAfterFailure();
      }
    }
  }

  Future<void> flushAndClose() async {
    if (_closed) {
      return;
    }

    try {
      await _file.setPosition(4);
      _file.writeFromSync(_uint32Le(36 + _audioBytesWritten));
      await _file.setPosition(40);
      _file.writeFromSync(_uint32Le(_audioBytesWritten));
      await _file.setPosition(_headerSize + _audioBytesWritten);
      await _file.flush();
    } finally {
      _closed = true;
      await _file.close();
    }
  }

  Uint8List _buildHeader({required int audioBytes}) {
    final byteRate = sampleRate * _blockAlign;
    final chunkSize = 36 + audioBytes;

    final bytes = Uint8List(_headerSize);
    final data = ByteData.sublistView(bytes);

    _writeAscii(bytes, 0, 'RIFF');
    data.setUint32(4, chunkSize, Endian.little);
    _writeAscii(bytes, 8, 'WAVE');
    _writeAscii(bytes, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, _blockAlign, Endian.little);
    data.setUint16(34, _bitsPerSample, Endian.little);
    _writeAscii(bytes, 36, 'data');
    data.setUint32(40, audioBytes, Endian.little);

    return bytes;
  }

  Uint8List _uint32Le(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
    return bytes;
  }

  void _writeAscii(Uint8List target, int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      target[offset + i] = value.codeUnitAt(i);
    }
  }

  void _closeAfterFailure() {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      _file.closeSync();
    } catch (error, stackTrace) {
      developer.log(
        'pcm_wav_file_close_after_failure_failed',
        name: 'PcmWavFileWriter',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
