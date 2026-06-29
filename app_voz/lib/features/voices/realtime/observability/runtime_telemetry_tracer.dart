import 'dart:async';

import '../voice_realtime_event.dart';
import '../voice_realtime_event_bus.dart';

class RuntimeTelemetryTracer {
  RuntimeTelemetryTracer({VoiceRealtimeEventBus? eventBus, this.capacity = 500})
    : assert(capacity > 0),
      eventBus = eventBus ?? VoiceRealtimeEventBus.instance {
    _buffer = List<VoiceRealtimeEvent?>.filled(capacity, null);
    _subscription = this.eventBus.stream.listen(_record);
  }

  final VoiceRealtimeEventBus eventBus;
  final int capacity;

  late final List<VoiceRealtimeEvent?> _buffer;
  late final StreamSubscription<VoiceRealtimeEvent> _subscription;
  int _nextIndex = 0;
  int _count = 0;

  int get length => _count;

  List<VoiceRealtimeEvent> getTraceChain(String correlationId) {
    if (correlationId.isEmpty) {
      return const [];
    }

    final events = _orderedEvents()
        .where((event) => event.correlationId == correlationId)
        .toList(growable: false);

    if (events.isEmpty) {
      return const [];
    }

    final byId = {for (final event in events) event.id: event};
    final roots = events
        .where(
          (event) =>
              event.causationId == null || !byId.containsKey(event.causationId),
        )
        .toList(growable: false);

    final result = <VoiceRealtimeEvent>[];
    final visited = <String>{};

    void visit(VoiceRealtimeEvent event) {
      if (!visited.add(event.id)) {
        return;
      }
      result.add(event);
      for (final child in events.where(
        (next) => next.causationId == event.id,
      )) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }

    for (final event in events) {
      visit(event);
    }

    return result;
  }

  void _record(VoiceRealtimeEvent event) {
    _buffer[_nextIndex] = event;
    _nextIndex = (_nextIndex + 1) % capacity;
    if (_count < capacity) {
      _count += 1;
    }
  }

  List<VoiceRealtimeEvent> _orderedEvents() {
    if (_count == 0) {
      return const [];
    }

    final events = <VoiceRealtimeEvent>[];
    final start = _count == capacity ? _nextIndex : 0;
    for (var i = 0; i < _count; i++) {
      final event = _buffer[(start + i) % capacity];
      if (event != null) {
        events.add(event);
      }
    }
    return events;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
