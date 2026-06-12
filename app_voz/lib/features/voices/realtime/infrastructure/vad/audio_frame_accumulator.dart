import 'dart:typed_data';

class AudioFrameAccumulator {
  AudioFrameAccumulator({this.frameSizeBytes = 320})
    : assert(frameSizeBytes > 0);

  final int frameSizeBytes;

  Uint8List _buffer = Uint8List(0);
  int _readOffset = 0;
  int _writeOffset = 0;

  int get pendingBytes => _writeOffset - _readOffset;

  bool get hasFrame => pendingBytes >= frameSizeBytes;

  void addChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }

    _ensureCapacity(chunk.length);
    _buffer.setRange(_writeOffset, _writeOffset + chunk.length, chunk);
    _writeOffset += chunk.length;
  }

  Uint8List? takeFrame() {
    if (!hasFrame) {
      return null;
    }

    final frame = Uint8List(frameSizeBytes);
    frame.setRange(0, frameSizeBytes, _buffer, _readOffset);
    _readOffset += frameSizeBytes;
    _compactIfNeeded();
    return frame;
  }

  void clear() {
    _readOffset = 0;
    _writeOffset = 0;
  }

  void _ensureCapacity(int additionalBytes) {
    final requiredBytes = pendingBytes + additionalBytes;
    if (_buffer.length >= _writeOffset + additionalBytes) {
      return;
    }

    final nextCapacity = _nextCapacity(requiredBytes);
    final next = Uint8List(nextCapacity);
    if (pendingBytes > 0) {
      next.setRange(0, pendingBytes, _buffer, _readOffset);
    }
    _writeOffset = pendingBytes;
    _readOffset = 0;
    _buffer = next;
  }

  int _nextCapacity(int requiredBytes) {
    var capacity = frameSizeBytes;
    while (capacity < requiredBytes) {
      capacity *= 2;
    }
    return capacity;
  }

  void _compactIfNeeded() {
    if (_readOffset == _writeOffset) {
      clear();
      return;
    }

    if (_readOffset < frameSizeBytes * 4) {
      return;
    }

    final bytes = pendingBytes;
    _buffer.setRange(0, bytes, _buffer, _readOffset);
    _readOffset = 0;
    _writeOffset = bytes;
  }
}
