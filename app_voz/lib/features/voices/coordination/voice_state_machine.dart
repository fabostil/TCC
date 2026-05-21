import 'package:flutter/foundation.dart';

import '../realtime/voice_realtime_events.dart';
import 'voice_diagnostics.dart';

enum VoiceState {
  idle,
  listening,
  processing,
  executing,
  recording,
  paused,
  recovering,
  error,
  disabled,
}

class VoiceStateSnapshot {
  const VoiceStateSnapshot({
    required this.state,
    this.previousState,
    this.ownerId,
    this.message,
    this.reason,
    this.updatedAt,
    this.recoveryAttempts = 0,
  });

  const VoiceStateSnapshot.initial()
    : state = VoiceState.idle,
      previousState = null,
      ownerId = null,
      message = null,
      reason = null,
      updatedAt = null,
      recoveryAttempts = 0;

  final VoiceState state;
  final VoiceState? previousState;
  final String? ownerId;
  final String? message;
  final String? reason;
  final DateTime? updatedAt;
  final int recoveryAttempts;

  bool get isListening => state == VoiceState.listening;

  bool get isBusy =>
      state == VoiceState.processing ||
      state == VoiceState.executing ||
      state == VoiceState.recovering;

  bool get microphoneReserved =>
      state == VoiceState.listening || state == VoiceState.recording;

  bool get canStartListening =>
      state == VoiceState.idle ||
      state == VoiceState.paused ||
      state == VoiceState.error ||
      state == VoiceState.recovering;

  VoiceStateSnapshot copyWith({
    VoiceState? state,
    VoiceState? previousState,
    String? ownerId,
    bool clearOwnerId = false,
    String? message,
    bool clearMessage = false,
    String? reason,
    bool clearReason = false,
    DateTime? updatedAt,
    int? recoveryAttempts,
  }) {
    return VoiceStateSnapshot(
      state: state ?? this.state,
      previousState: previousState ?? this.previousState,
      ownerId: clearOwnerId ? null : ownerId ?? this.ownerId,
      message: clearMessage ? null : message ?? this.message,
      reason: clearReason ? null : reason ?? this.reason,
      updatedAt: updatedAt ?? this.updatedAt,
      recoveryAttempts: recoveryAttempts ?? this.recoveryAttempts,
    );
  }
}

class VoiceStateMachine extends ChangeNotifier {
  VoiceStateMachine({VoiceDiagnostics? diagnostics})
    : diagnostics = diagnostics ?? VoiceDiagnostics();

  final VoiceDiagnostics diagnostics;

  VoiceStateSnapshot _snapshot = const VoiceStateSnapshot.initial();

  VoiceStateSnapshot get snapshot => _snapshot;

  VoiceState get state => _snapshot.state;

  bool canTransitionTo(VoiceState next) {
    final current = _snapshot.state;

    if (current == next) {
      return true;
    }

    if (current == VoiceState.disabled) {
      return next == VoiceState.idle;
    }

    if (current == VoiceState.recording) {
      return next == VoiceState.paused ||
          next == VoiceState.idle ||
          next == VoiceState.error ||
          next == VoiceState.disabled;
    }

    if (current == VoiceState.recovering) {
      return next == VoiceState.listening ||
          next == VoiceState.idle ||
          next == VoiceState.error ||
          next == VoiceState.disabled ||
          next == VoiceState.recording;
    }

    return true;
  }

  VoiceStateSnapshot transitionTo(
    VoiceState next, {
    String? ownerId,
    String? message,
    String? reason,
    DateTime? now,
    bool force = false,
    int? recoveryAttempts,
  }) {
    if (!force && !canTransitionTo(next)) {
      diagnostics.record(
        VoiceDiagnosticEventType.error,
        ownerId: ownerId ?? _snapshot.ownerId,
        reason: reason ?? 'invalid_transition',
        message:
            'Transicao de voz bloqueada: ${_snapshot.state.name} -> ${next.name}.',
      );
      return _snapshot;
    }

    final previous = _snapshot.state;
    _snapshot = VoiceStateSnapshot(
      state: next,
      previousState: previous,
      ownerId: ownerId ?? _snapshot.ownerId,
      message: message ?? _snapshot.message,
      reason: reason,
      updatedAt: now ?? DateTime.now(),
      recoveryAttempts: recoveryAttempts ?? _snapshot.recoveryAttempts,
    );

    diagnostics.record(
      VoiceDiagnosticEventType.stateTransition,
      ownerId: _snapshot.ownerId,
      reason: reason,
      message: '${previous.name} -> ${next.name}',
      metadata: {'message': _snapshot.message},
      now: _snapshot.updatedAt,
    );
    diagnostics.eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_state_machine',
        previousState: previous.name,
        nextState: next.name,
        ownerId: _snapshot.ownerId,
        reason: reason,
        message: _snapshot.message,
        metadata: {'recoveryAttempts': _snapshot.recoveryAttempts},
      ),
    );
    notifyListeners();
    return _snapshot;
  }

  void incrementRecoveryAttempts() {
    _snapshot = _snapshot.copyWith(
      recoveryAttempts: _snapshot.recoveryAttempts + 1,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void resetRecoveryAttempts() {
    if (_snapshot.recoveryAttempts == 0) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      recoveryAttempts: 0,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void reset() {
    _snapshot = const VoiceStateSnapshot.initial();
    diagnostics.clear();
    notifyListeners();
  }
}
