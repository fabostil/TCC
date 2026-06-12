import 'dart:async';

import '../nlu/voice_intent.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'intent_response_formatter.dart';
import 'stub_text_to_speech_engine.dart';
import 'text_to_speech_engine.dart';

class VoiceResponseBridge {
  VoiceResponseBridge({
    VoiceRealtimeEventBus? eventBus,
    TextToSpeechEngine? ttsEngine,
    this.formatter = const IntentResponseFormatter(),
  }) : eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       ttsEngine =
           ttsEngine ??
           StubTextToSpeechEngine(
             eventBus: eventBus ?? VoiceRealtimeEventBus.instance,
           );

  static final VoiceResponseBridge instance = VoiceResponseBridge();

  final VoiceRealtimeEventBus eventBus;
  final TextToSpeechEngine ttsEngine;
  final IntentResponseFormatter formatter;

  final Set<String> _respondedCorrelations = {};
  StreamSubscription<VoiceCommandInterpretedEvent>? _commandSubscription;
  StreamSubscription<VoiceCommandFailedEvent>? _failureSubscription;
  StreamSubscription<VoiceCommandConfirmationRequiredEvent>?
  _confirmationSubscription;
  StreamSubscription<VoiceCommandConfirmationResolvedEvent>?
  _confirmationResolvedSubscription;
  bool _started = false;

  bool get isStarted => _started;

  void start() {
    if (_started) {
      return;
    }
    _commandSubscription = eventBus.on<VoiceCommandInterpretedEvent>().listen(
      _handleCommandInterpreted,
    );
    _failureSubscription = eventBus.on<VoiceCommandFailedEvent>().listen(
      _handleCommandFailed,
    );
    _confirmationSubscription = eventBus
        .on<VoiceCommandConfirmationRequiredEvent>()
        .listen(_handleConfirmationRequired);
    _confirmationResolvedSubscription = eventBus
        .on<VoiceCommandConfirmationResolvedEvent>()
        .listen(_handleConfirmationResolved);
    _started = true;
  }

  Future<void> dispose() async {
    await _commandSubscription?.cancel();
    await _failureSubscription?.cancel();
    await _confirmationSubscription?.cancel();
    await _confirmationResolvedSubscription?.cancel();
    _commandSubscription = null;
    _failureSubscription = null;
    _confirmationSubscription = null;
    _confirmationResolvedSubscription = null;
    _respondedCorrelations.clear();
    _started = false;
    await ttsEngine.dispose();
  }

  Future<void> _handleCommandInterpreted(
    VoiceCommandInterpretedEvent event,
  ) async {
    if (!_respondedCorrelations.add(event.correlationId)) {
      return;
    }

    if (event.intent is DeleteLastRecordingIntent) {
      return;
    }
    if (event.intent is ConfirmIntent || event.intent is CancelIntent) {
      return;
    }

    final response = formatter.format(event.intent);
    await _speakSafely(
      response,
      event.correlationId,
      causationId: event.id,
      intent: event.intent,
    );
  }

  Future<void> _speakSafely(
    String text,
    String correlationId, {
    String? causationId,
    VoiceIntent? intent,
  }) async {
    try {
      await ttsEngine.speak(text, correlationId);
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_response_bridge',
          reason: 'tts_speak_failed',
          correlationId: correlationId,
          causationId: causationId,
          metadata: {
            'error': error.toString(),
            if (intent != null) 'intentType': intent.runtimeType.toString(),
          },
        ),
      );
    }
  }

  Future<void> _handleCommandFailed(VoiceCommandFailedEvent event) async {
    await _speakSafely(
      formatter.formatFailure(event.reason ?? ''),
      event.correlationId,
      causationId: event.id,
      intent: event.intent,
    );
  }

  Future<void> _handleConfirmationRequired(
    VoiceCommandConfirmationRequiredEvent event,
  ) async {
    await _speakSafely(
      formatter.formatConfirmation(event.action, event.intent),
      event.correlationId,
      causationId: event.id,
      intent: event.intent,
    );
  }

  Future<void> _handleConfirmationResolved(
    VoiceCommandConfirmationResolvedEvent event,
  ) async {
    await _speakSafely(
      formatter.formatConfirmationResolved(
        event.action,
        event.intent,
        approved: event.approved,
      ),
      event.correlationId,
      causationId: event.id,
      intent: event.intent,
    );
  }
}
