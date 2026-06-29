import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'wake_word_engine.dart';

const String _porcupineLibraryName = 'libpv_porcupine.so';
const int _porcupineKeywordCount = 1;
const int _porcupineDetectedIndex = 0;

typedef _PvPorcupineInitNative =
    Int32 Function(
      Pointer<Utf8> accessKey,
      Pointer<Utf8> modelPath,
      Int32 numKeywords,
      Pointer<Pointer<Utf8>> keywordPaths,
      Pointer<Float> sensitivities,
      Pointer<Pointer<Void>> object,
    );

typedef _PvPorcupineInitDart =
    int Function(
      Pointer<Utf8> accessKey,
      Pointer<Utf8> modelPath,
      int numKeywords,
      Pointer<Pointer<Utf8>> keywordPaths,
      Pointer<Float> sensitivities,
      Pointer<Pointer<Void>> object,
    );

typedef _PvPorcupineProcessNative =
    Int32 Function(
      Pointer<Void> object,
      Pointer<Int16> frame,
      Pointer<Int32> keywordIndex,
    );

typedef _PvPorcupineProcessDart =
    int Function(
      Pointer<Void> object,
      Pointer<Int16> frame,
      Pointer<Int32> keywordIndex,
    );

typedef _PvPorcupineDeleteNative = Void Function(Pointer<Void> object);
typedef _PvPorcupineDeleteDart = void Function(Pointer<Void> object);

class PicovoicePorcupineEngine implements WakeWordEngine {
  PicovoicePorcupineEngine({
    DynamicLibrary Function()? libraryLoader,
    StubWakeWordEngine? fallbackEngine,
  }) : _libraryLoader =
           libraryLoader ?? (() => DynamicLibrary.open(_porcupineLibraryName)),
       _fallbackEngine = fallbackEngine ?? StubWakeWordEngine();

  final DynamicLibrary Function() _libraryLoader;
  final StubWakeWordEngine _fallbackEngine;

  _PvPorcupineProcessDart? _process;
  _PvPorcupineDeleteDart? _delete;
  Pointer<Void>? _object;
  bool _usingFallback = true;
  bool _disposed = false;

  @override
  Future<void> init({
    String? accessKey,
    String? modelPath,
    required String keywordPath,
    required double sensitivity,
  }) async {
    _disposed = false;
    _disposeNativeObject();
    await _fallbackEngine.init(
      keywordPath: keywordPath,
      sensitivity: sensitivity,
    );

    if (accessKey == null ||
        accessKey.isEmpty ||
        modelPath == null ||
        modelPath.isEmpty) {
      await _activateFallback(
        keywordPath: keywordPath,
        sensitivity: sensitivity,
        reason: 'missing_access_key_or_model_path',
      );
      return;
    }

    Pointer<Utf8>? accessKeyPointer;
    Pointer<Utf8>? modelPathPointer;
    Pointer<Utf8>? keywordPathPointer;
    Pointer<Pointer<Utf8>>? keywordPathsPointer;
    Pointer<Float>? sensitivitiesPointer;
    Pointer<Pointer<Void>>? objectPointer;

    try {
      final library = _libraryLoader();
      final init = library
          .lookupFunction<_PvPorcupineInitNative, _PvPorcupineInitDart>(
            'pv_porcupine_init',
          );
      final process = library
          .lookupFunction<_PvPorcupineProcessNative, _PvPorcupineProcessDart>(
            'pv_porcupine_process',
          );
      final delete = library
          .lookupFunction<_PvPorcupineDeleteNative, _PvPorcupineDeleteDart>(
            'pv_porcupine_delete',
          );

      accessKeyPointer = accessKey.toNativeUtf8();
      modelPathPointer = modelPath.toNativeUtf8();
      keywordPathPointer = keywordPath.toNativeUtf8();
      keywordPathsPointer = calloc<Pointer<Utf8>>(_porcupineKeywordCount);
      sensitivitiesPointer = calloc<Float>(_porcupineKeywordCount);
      objectPointer = calloc<Pointer<Void>>();

      keywordPathsPointer[0] = keywordPathPointer;
      sensitivitiesPointer[0] = sensitivity.clamp(0, 1).toDouble();

      final status = init(
        accessKeyPointer,
        modelPathPointer,
        _porcupineKeywordCount,
        keywordPathsPointer,
        sensitivitiesPointer,
        objectPointer,
      );
      final object = objectPointer.value;

      if (status != 0 || object == nullptr) {
        if (object != nullptr) {
          delete(object);
        }
        await _activateFallback(
          keywordPath: keywordPath,
          sensitivity: sensitivity,
          reason: 'native_init_failed_status_$status',
        );
        return;
      }

      _process = process;
      _delete = delete;
      _object = object;
      _usingFallback = false;
    } catch (error, stackTrace) {
      developer.log(
        'Picovoice Porcupine unavailable; using wake-word stub fallback.',
        name: 'app_voz.wakeword',
        error: error,
        stackTrace: stackTrace,
      );
      await _activateFallback(
        keywordPath: keywordPath,
        sensitivity: sensitivity,
        reason: 'native_library_unavailable',
      );
    } finally {
      if (accessKeyPointer != null) {
        calloc.free(accessKeyPointer);
      }
      if (modelPathPointer != null) {
        calloc.free(modelPathPointer);
      }
      if (keywordPathPointer != null) {
        calloc.free(keywordPathPointer);
      }
      if (keywordPathsPointer != null) {
        calloc.free(keywordPathsPointer);
      }
      if (sensitivitiesPointer != null) {
        calloc.free(sensitivitiesPointer);
      }
      if (objectPointer != null) {
        calloc.free(objectPointer);
      }
    }
  }

  @override
  bool processFrame(Int16List frame) {
    if (_disposed) {
      return false;
    }
    if (_usingFallback) {
      return _fallbackEngine.processFrame(frame);
    }

    final process = _process;
    final object = _object;
    if (process == null || object == null || object == nullptr) {
      return false;
    }

    Pointer<Int16>? nativeFrame;
    Pointer<Int32>? keywordIndexPointer;
    try {
      nativeFrame = calloc<Int16>(frame.length);
      nativeFrame.asTypedList(frame.length).setAll(0, frame);
      keywordIndexPointer = calloc<Int32>();
      keywordIndexPointer.value = -1;

      final status = process(object, nativeFrame, keywordIndexPointer);
      if (status != 0) {
        developer.log(
          'Picovoice Porcupine process failed with status $status.',
          name: 'app_voz.wakeword',
        );
        _disposeNativeObject();
        _usingFallback = true;
        return _fallbackEngine.processFrame(frame);
      }

      return keywordIndexPointer.value == _porcupineDetectedIndex;
    } catch (error, stackTrace) {
      developer.log(
        'Picovoice Porcupine process failed; keeping audio loop alive.',
        name: 'app_voz.wakeword',
        error: error,
        stackTrace: stackTrace,
      );
      _disposeNativeObject();
      _usingFallback = true;
      return _fallbackEngine.processFrame(frame);
    } finally {
      if (nativeFrame != null) {
        calloc.free(nativeFrame);
      }
      if (keywordIndexPointer != null) {
        calloc.free(keywordIndexPointer);
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _disposeNativeObject();
    await _fallbackEngine.dispose();
    _usingFallback = true;
  }

  Future<void> _activateFallback({
    required String keywordPath,
    required double sensitivity,
    required String reason,
  }) async {
    developer.log(
      'Wake-word native engine fallback active: $reason.',
      name: 'app_voz.wakeword',
    );
    _disposeNativeObject();
    await _fallbackEngine.init(
      keywordPath: keywordPath,
      sensitivity: sensitivity,
    );
    _usingFallback = true;
  }

  void _disposeNativeObject() {
    final object = _object;
    final delete = _delete;
    _object = null;
    _process = null;
    _delete = null;

    if (object == null || object == nullptr || delete == null) {
      return;
    }

    try {
      delete(object);
    } catch (error, stackTrace) {
      developer.log(
        'Picovoice Porcupine delete failed.',
        name: 'app_voz.wakeword',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
