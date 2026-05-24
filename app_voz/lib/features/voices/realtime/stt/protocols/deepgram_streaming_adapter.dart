import 'dart:convert';

import '../../voice_realtime_event_bus.dart';
import '../cloud_streaming_speech_recognizer.dart';

class DeepgramStreamingAdapter {
  DeepgramStreamingAdapter({required this.apiKey, required Uri endpoint})
    : endpoint = _withDefaultQuery(endpoint);

  static const String apiKeyFromEnvironment = String.fromEnvironment(
    'DEEPGRAM_API_KEY',
    defaultValue: '',
  );

  static const String endpointFromEnvironment = String.fromEnvironment(
    'DEEPGRAM_STREAMING_STT_WEBSOCKET_URL',
    defaultValue: '',
  );

  static const String closeStreamMessage = '{"type":"CloseStream"}';

  final String apiKey;
  final Uri endpoint;

  bool get isConfigured => apiKey.isNotEmpty && endpoint.host.isNotEmpty;

  Map<String, dynamic> get headers => {'Authorization': 'Token $apiKey'};

  CloudStreamingSpeechRecognizer createRecognizer({
    VoiceRealtimeEventBus? eventBus,
    WebSocketTransportConnector? connector,
    Duration handshakeTimeout = const Duration(seconds: 5),
  }) {
    return CloudStreamingSpeechRecognizer(
      endpoint: endpoint,
      eventBus: eventBus,
      connector: connector,
      handshakeTimeout: handshakeTimeout,
      closeMessage: closeStreamMessage,
      headers: headers,
      responseParser: parseServerResponse,
    );
  }

  static StreamingSpeechResult? parseServerResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final channel = decoded['channel'];
      if (channel is! Map<String, dynamic>) {
        return null;
      }

      final alternatives = channel['alternatives'];
      if (alternatives is! List || alternatives.isEmpty) {
        return null;
      }

      final first = alternatives.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }

      final transcript = first['transcript'];
      if (transcript is! String || transcript.trim().isEmpty) {
        return null;
      }

      return StreamingSpeechResult(
        text: transcript.trim(),
        isFinal: decoded['is_final'] == true,
      );
    } on FormatException {
      return null;
    }
  }

  static Uri? endpointFromConfiguredEnvironment() {
    final endpoint = Uri.tryParse(endpointFromEnvironment);
    if (endpoint == null ||
        !endpoint.hasScheme ||
        (endpoint.scheme != 'ws' && endpoint.scheme != 'wss') ||
        endpoint.host.isEmpty) {
      return null;
    }
    return endpoint;
  }

  static Uri _withDefaultQuery(Uri endpoint) {
    return endpoint.replace(
      queryParameters: {
        'model': 'nova-2',
        'encoding': 'linear16',
        'sample_rate': '16000',
        'channels': '1',
        'interim_results': 'true',
        'punctuate': 'true',
        ...endpoint.queryParameters,
      },
    );
  }
}
