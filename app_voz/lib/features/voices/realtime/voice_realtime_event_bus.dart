import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_realtime_event.dart';
import 'voice_realtime_events.dart';

class VoiceRealtimeEventBus extends ChangeNotifier {
  VoiceRealtimeEventBus({this.maxEvents = 300});

  static final VoiceRealtimeEventBus instance = VoiceRealtimeEventBus();

  final int maxEvents;
  final List<VoiceRealtimeEvent> _timeline = [];
  final Set<String> _cancelledCorrelationIds = {};
  final StreamController<VoiceRealtimeEvent> _controller =
      StreamController<VoiceRealtimeEvent>.broadcast(sync: true);
  final List<VoiceRealtimeEvent> _pendingDispatch = [];
  bool _isDispatching = false;

  List<VoiceRealtimeEvent> get timeline => List.unmodifiable(_timeline);

  VoiceRealtimeEvent? get latest => _timeline.isEmpty ? null : _timeline.last;

  Stream<VoiceRealtimeEvent> get stream => _controller.stream;

  Stream<T> on<T extends VoiceRealtimeEvent>() {
    return stream.where((event) => event is T).cast<T>();
  }

  Stream<VoiceRealtimeEvent> onType(VoiceRealtimeEventType type) {
    return stream.where((event) => event.type == type);
  }

  bool isChainCancelled(String correlationId) {
    return _cancelledCorrelationIds.contains(correlationId);
  }

  bool publish(VoiceRealtimeEvent event) {
    if (event.cancelable && isChainCancelled(event.correlationId)) {
      return false;
    }

    _append(event);
    if (_isDispatching) {
      _pendingDispatch.add(event);
    } else {
      _dispatch(event);
    }
    notifyListeners();
    return true;
  }

  VoiceRealtimeEvent cancelChain(
    String correlationId, {
    String source = 'voice_runtime',
    String? ownerId,
    String? reason,
    String? message,
  }) {
    _cancelledCorrelationIds.add(correlationId);
    final event = EventChainCancelledEvent(
      source: source,
      cancelledCorrelationId: correlationId,
      ownerId: ownerId,
      reason: reason,
      message: message,
    );
    publish(event);
    return event;
  }

  List<VoiceRealtimeEvent> eventsForCorrelation(String correlationId) {
    return _timeline
        .where((event) => event.correlationId == correlationId)
        .toList(growable: false);
  }

  void _append(VoiceRealtimeEvent event) {
    _timeline.add(event);
    if (_timeline.length > maxEvents) {
      _timeline.removeRange(0, _timeline.length - maxEvents);
    }
  }

  void _dispatch(VoiceRealtimeEvent event) {
    _isDispatching = true;
    try {
      _controller.add(event);
      while (_pendingDispatch.isNotEmpty) {
        _controller.add(_pendingDispatch.removeAt(0));
      }
    } finally {
      _isDispatching = false;
    }
  }

  void clearForTesting() {
    _timeline.clear();
    _cancelledCorrelationIds.clear();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    await _controller.close();
  }
}
