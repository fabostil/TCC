import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../nlu/voice_intent.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import 'handlers/metronome_command_handler.dart';
import 'handlers/playback_command_handler.dart';
import 'handlers/track_command_handler.dart';
import 'voice_command_handler.dart';

class VoiceCommandDispatcher {
  VoiceCommandDispatcher({
    VoiceRealtimeEventBus? eventBus,
    Map<Type, VoiceCommandHandler<dynamic>>? handlers,
    this.processedHistoryLimit = 100,
  }) : assert(processedHistoryLimit > 0),
       eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _handlers =
           handlers ??
           _defaultHandlers(eventBus ?? VoiceRealtimeEventBus.instance);

  static final VoiceCommandDispatcher instance = VoiceCommandDispatcher();

  final VoiceRealtimeEventBus eventBus;
  final int processedHistoryLimit;
  final Map<Type, VoiceCommandHandler<dynamic>> _handlers;
  final Set<String> _processedCorrelationIds = {};
  final Queue<String> _processedCorrelationOrder = Queue<String>();

  StreamSubscription<VoiceCommandInterpretedEvent>? _subscription;
  Future<void> _lastCommand = Future<void>.value();
  var _started = false;

  bool get isStarted => _started;

  @visibleForTesting
  Future<void> get idle => _lastCommand;

  void start() {
    if (_started) {
      return;
    }
    _subscription = eventBus.on<VoiceCommandInterpretedEvent>().listen(
      _enqueue,
    );
    _started = true;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _lastCommand;
    _processedCorrelationIds.clear();
    _processedCorrelationOrder.clear();
    _started = false;
  }

  void _enqueue(VoiceCommandInterpretedEvent event) {
    if (!_rememberCorrelation(event.correlationId)) {
      _publishIgnored(
        event,
        reason: 'duplicate_command_ignored',
        metadata: {'intentType': event.intent.runtimeType.toString()},
      );
      return;
    }

    _lastCommand = _lastCommand.then((_) => _dispatch(event));
    unawaited(_lastCommand);
  }

  Future<void> _dispatch(VoiceCommandInterpretedEvent event) async {
    final intent = event.intent;
    if (intent is UnknownIntent) {
      _publishIgnored(
        event,
        reason: 'unknown_intent_ignored',
        metadata: {'rawText': intent.rawText},
      );
      return;
    }

    final handler = _handlers[intent.runtimeType];
    if (handler == null) {
      _publishIgnored(
        event,
        reason: 'command_handler_not_registered',
        metadata: {'intentType': intent.runtimeType.toString()},
      );
      return;
    }

    try {
      await _invokeHandler(handler, intent, event.correlationId);
      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'voice_command_dispatcher',
          previousState: 'commandQueued',
          nextState: 'commandDispatched',
          reason: 'command_handler_completed',
          correlationId: event.correlationId,
          causationId: event.id,
          metadata: {'intentType': intent.runtimeType.toString()},
        ),
      );
    } catch (error) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_command_dispatcher',
          reason: 'command_handler_failed',
          correlationId: event.correlationId,
          causationId: event.id,
          metadata: {
            'error': error.toString(),
            'intentType': intent.runtimeType.toString(),
          },
        ),
      );
    }
  }

  Future<void> _invokeHandler(
    VoiceCommandHandler<dynamic> handler,
    VoiceIntent intent,
    String correlationId,
  ) {
    return handler.handle(intent, correlationId);
  }

  bool _rememberCorrelation(String correlationId) {
    if (_processedCorrelationIds.contains(correlationId)) {
      return false;
    }

    _processedCorrelationIds.add(correlationId);
    _processedCorrelationOrder.addLast(correlationId);

    while (_processedCorrelationOrder.length > processedHistoryLimit) {
      final removed = _processedCorrelationOrder.removeFirst();
      _processedCorrelationIds.remove(removed);
    }
    return true;
  }

  void _publishIgnored(
    VoiceCommandInterpretedEvent event, {
    required String reason,
    Map<String, Object?> metadata = const {},
  }) {
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_command_dispatcher',
        previousState: 'commandQueued',
        nextState: 'commandIgnored',
        reason: reason,
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: metadata,
      ),
    );
  }

  static Map<Type, VoiceCommandHandler<dynamic>> _defaultHandlers(
    VoiceRealtimeEventBus eventBus,
  ) {
    return {
      MetronomeIntent: MetronomeCommandHandler(
        service: StubMetronomeService(),
        eventBus: eventBus,
      ),
      PlaybackIntent: PlaybackCommandHandler(
        service: StubPlaybackService(),
        eventBus: eventBus,
      ),
      TrackIntent: TrackCommandHandler(
        service: StubTrackService(),
        eventBus: eventBus,
      ),
    };
  }
}
