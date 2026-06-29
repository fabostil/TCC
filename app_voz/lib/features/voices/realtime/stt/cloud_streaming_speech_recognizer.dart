import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'streaming_speech_recognizer.dart';

typedef WebSocketTransportConnector =
    Future<WebSocketTransport> Function(
      Uri uri, {
      Duration timeout,
      Map<String, dynamic>? headers,
    });

typedef CloudSpeechResponseParser = StreamingSpeechResult? Function(String raw);

abstract class WebSocketTransport {
  Stream<dynamic> get stream;
  void add(Object? data);
  Future<void> close([int? closeCode, String? closeReason]);
}

class NativeWebSocketTransport implements WebSocketTransport {
  NativeWebSocketTransport(this._socket);

  static Future<WebSocketTransport> connect(
    Uri uri, {
    Duration timeout = const Duration(seconds: 5),
    Map<String, dynamic>? headers,
  }) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    ).timeout(timeout);
    return NativeWebSocketTransport(socket);
  }

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void add(Object? data) {
    _socket.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    return _socket.close(closeCode, closeReason);
  }
}

/// Adapter generico para STT streaming em nuvem via WebSocket.
///
/// Esta classe nao implementa protocolo proprietario de nenhum provedor. Ela
/// apenas transporta PCM16 mono 16kHz como binario e converte respostas JSON
/// simples em eventos realtime. Adaptadores concretos devem encapsular
/// autenticacao, envelopes e mensagens especificas de cada fornecedor.
class CloudStreamingSpeechRecognizer implements StreamingSpeechRecognizer {
  CloudStreamingSpeechRecognizer({
    required this.endpoint,
    VoiceRealtimeEventBus? eventBus,
    WebSocketTransportConnector? connector,
    this.handshakeTimeout = const Duration(seconds: 5),
    this.closeMessage,
    this.headers = const {},
    CloudSpeechResponseParser? responseParser,
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       responseParser = responseParser ?? parseGenericServerResponse,
       _connector = connector ?? NativeWebSocketTransport.connect;

  static const String endpointFromEnvironment = String.fromEnvironment(
    'STREAMING_STT_WEBSOCKET_URL',
    defaultValue: '',
  );

  static const String closeMessageFromEnvironment = String.fromEnvironment(
    'STREAMING_STT_CLOSE_MESSAGE',
    defaultValue: '',
  );

  final Uri endpoint;
  final VoiceRealtimeEventBus eventBus;
  final WebSocketTransportConnector _connector;
  final Duration handshakeTimeout;
  final String? closeMessage;
  final Map<String, dynamic> headers;
  final CloudSpeechResponseParser responseParser;

  WebSocketTransport? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  String? _correlationId;
  bool _recognizing = false;
  bool _closing = false;

  @override
  Future<void> initializeRecognizer() async {}

  @override
  Future<void> startRecognition(String correlationId) async {
    await stopRecognition();
    _correlationId = correlationId;
    _closing = false;

    try {
      final socket = await _connector(
        endpoint,
        timeout: handshakeTimeout,
        headers: headers.isEmpty ? null : headers,
      ).timeout(handshakeTimeout);
      _socket = socket;
      _recognizing = true;
      _socketSubscription = socket.stream.listen(
        _handleServerMessage,
        onError: (Object error, StackTrace stackTrace) {
          _handleFailure(error, stackTrace);
        },
        onDone: () {
          if (!_closing && _recognizing) {
            _publishFailure('websocket_closed_unexpectedly');
          }
          _recognizing = false;
          _socket = null;
        },
      );
    } on Object catch (error, stackTrace) {
      _handleFailure(error, stackTrace);
    }
  }

  @override
  void feedAudioChunk(Uint8List chunk) {
    final socket = _socket;
    if (!_recognizing || _closing || socket == null) {
      return;
    }

    try {
      socket.add(chunk);
    } on Object catch (error, stackTrace) {
      _handleFailure(error, stackTrace);
    }
  }

  @override
  Future<void> stopRecognition() async {
    if (!_recognizing && _socket == null && _socketSubscription == null) {
      return;
    }

    _closing = true;
    final socket = _socket;
    _recognizing = false;
    _socket = null;

    try {
      final message = closeMessage;
      if (socket != null && message != null && message.isNotEmpty) {
        socket.add(message);
      }
      await socket?.close();
    } on Object catch (error, stackTrace) {
      _handleFailure(error, stackTrace);
    } finally {
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      _correlationId = null;
      _closing = false;
    }
  }

  @override
  Future<void> dispose() async {
    await stopRecognition();
  }

  void _handleServerMessage(dynamic message) {
    final parsed = responseParser(_messageToText(message));
    if (parsed == null) {
      return;
    }

    eventBus.publish(
      SpeechResultReceivedEvent(
        source: 'cloud_streaming_speech_recognizer',
        text: parsed.text,
        isFinal: parsed.isFinal,
        correlationId: _correlationId,
        reason: parsed.isFinal ? 'cloud_final_result' : 'cloud_partial_result',
      ),
    );
  }

  String _messageToText(dynamic message) {
    if (message is String) {
      return message;
    }
    if (message is List<int>) {
      return utf8.decode(message);
    }
    return message.toString();
  }

  static StreamingSpeechResult? parseGenericServerResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final text = _readText(decoded);
      if (text == null || text.trim().isEmpty) {
        return null;
      }

      return StreamingSpeechResult(text: text, isFinal: _readIsFinal(decoded));
    } on FormatException {
      return null;
    }
  }

  static String? _readText(Map<String, dynamic> decoded) {
    final direct = decoded['text'] ?? decoded['transcript'];
    if (direct is String) {
      return direct;
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['text'] ?? result['transcript'];
      if (nested is String) {
        return nested;
      }
    }
    return null;
  }

  static bool _readIsFinal(Map<String, dynamic> decoded) {
    final value = decoded['isFinal'] ?? decoded['is_final'] ?? decoded['final'];
    if (value is bool) {
      return value;
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['isFinal'] ?? result['is_final'] ?? result['final'];
      if (nested is bool) {
        return nested;
      }
    }
    return false;
  }

  void _handleFailure(Object error, StackTrace _) {
    _publishFailure(error.toString());
    unawaited(_cleanupAfterFailure());
  }

  void _publishFailure(String reason) {
    eventBus.publish(
      SpeechListeningFailedEvent(
        source: 'cloud_streaming_speech_recognizer',
        reason: reason,
        message: 'Falha no STT streaming em nuvem: $reason',
        correlationId: _correlationId,
      ),
    );
  }

  Future<void> _cleanupAfterFailure() async {
    _closing = true;
    _recognizing = false;
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } on Object {
      // Best effort cleanup after transport failure.
    } finally {
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      _correlationId = null;
      _closing = false;
    }
  }
}

class StreamingSpeechResult {
  const StreamingSpeechResult({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}
