import 'dart:async';

import 'package:flutter/foundation.dart';

import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';

typedef VoiceRuntimePredicate = bool Function();
typedef VoiceRuntimeRecoverAction = Future<void> Function();

class VoiceRuntimeRegistry extends ChangeNotifier {
  VoiceRuntimeRegistry({VoiceRealtimeEventBus? eventBus})
    : eventBus = eventBus ?? VoiceRealtimeEventBus.instance {
    _ownershipRequestSubscription = this.eventBus
        .on<VoiceOwnershipRequestedEvent>()
        .listen(_handleOwnershipRequested);
  }

  static final VoiceRuntimeRegistry instance = VoiceRuntimeRegistry();

  final VoiceRealtimeEventBus eventBus;

  String? _activeOwnerId;
  RuntimeOwnership _ownership = const RuntimeOwnership.none();
  VoiceRuntimeRouteContext? _activeRouteContext;
  VoiceRuntimeSession? _activeVoiceSession;
  int _sessionToken = 0;
  late final StreamSubscription<VoiceOwnershipRequestedEvent>
  _ownershipRequestSubscription;

  String? get activeOwnerId => _activeOwnerId;

  RuntimeOwnership get ownership => _ownership;

  VoiceRuntimeRouteContext? get activeRouteContext => _activeRouteContext;

  VoiceRuntimeSession? get activeVoiceSession {
    _clearStaleVoiceSession();
    return _activeVoiceSession;
  }

  bool get hasActiveVoiceSession => activeVoiceSession != null;

  Map<String, Object?> snapshotMetadata() {
    final route = _activeRouteContext;
    final session = activeVoiceSession;
    return Map.unmodifiable({
      'activeOwnerId': _activeOwnerId,
      'ownershipOwnerId': _ownership.ownerId,
      'ownershipReason': _ownership.reason,
      'routeId': route?.routeId,
      'routeName': route?.routeName,
      'routeMetadata': route == null ? null : Map.unmodifiable(route.metadata),
      'sessionToken': session?.token,
      'sessionOwnerId': session?.ownerId,
      'sessionRouteId': session?.routeId,
      'sessionMetadata': session == null
          ? null
          : Map.unmodifiable(session.metadata),
    });
  }

  void setActiveOwner(String? ownerId) {
    _activeOwnerId = ownerId;
    notifyListeners();
  }

  bool requestOwnership({
    required String requesterId,
    String source = 'runtime_registry',
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) {
    return eventBus.publish(
      VoiceOwnershipRequestedEvent(
        source: source,
        requesterId: requesterId,
        reason: reason,
        correlationId: correlationId,
        causationId: causationId,
        metadata: metadata,
      ),
    );
  }

  bool hasOwnership(String? ownerId) {
    if (ownerId == null || !_ownership.isOwned) {
      return false;
    }
    return _ownership.ownerId == ownerId;
  }

  bool canMutate({required String source, String? ownerId}) {
    if (_isTrustedRuntimeSource(source)) {
      return true;
    }
    return hasOwnership(ownerId);
  }

  void revokeOwnership({
    String? ownerId,
    String source = 'runtime_registry',
    String? reason,
    String? correlationId,
    String? causationId,
  }) {
    if (!_ownership.isOwned) {
      return;
    }
    if (ownerId != null && _ownership.ownerId != ownerId) {
      return;
    }
    final revokedOwnerId = _ownership.ownerId!;
    _ownership = const RuntimeOwnership.none();
    if (_activeOwnerId == revokedOwnerId) {
      _activeOwnerId = null;
    }
    eventBus.publish(
      VoiceOwnershipRevokedEvent(
        source: source,
        ownerId: revokedOwnerId,
        reason: reason,
        correlationId: correlationId,
        causationId: causationId,
      ),
    );
    notifyListeners();
  }

  void registerRouteContext({
    required String routeId,
    String? routeName,
    Map<String, Object?> metadata = const {},
  }) {
    final previousRouteId = _activeRouteContext?.routeId;
    _activeRouteContext = VoiceRuntimeRouteContext(
      routeId: routeId,
      routeName: routeName,
      metadata: metadata,
    );
    eventBus.publish(
      VoiceRouteContextChangedEvent(
        source: 'runtime_registry',
        routeId: routeId,
        routeName: routeName,
        previousRouteId: previousRouteId,
        reason: 'route_context_registered',
        metadata: metadata,
      ),
    );
    notifyListeners();
  }

  void clearRouteContext({String? routeId}) {
    if (routeId != null && _activeRouteContext?.routeId != routeId) {
      return;
    }
    final previousRouteId = _activeRouteContext?.routeId;
    _activeRouteContext = null;
    _clearVoiceSession();
    eventBus.publish(
      VoiceRouteContextChangedEvent(
        source: 'runtime_registry',
        previousRouteId: previousRouteId,
        reason: 'route_context_cleared',
        metadata: {'clearedRouteId': routeId},
      ),
    );
    notifyListeners();
  }

  int registerVoiceSession({
    required String ownerId,
    required VoiceRuntimePredicate shouldRecover,
    required VoiceRuntimeRecoverAction recover,
    VoiceRuntimePredicate? isAlive,
    String? routeId,
    Map<String, Object?> metadata = const {},
  }) {
    _sessionToken += 1;
    _activeOwnerId = ownerId;
    if (!_ownership.isOwned) {
      _grantOwnership(
        ownerId: ownerId,
        source: 'runtime_registry',
        reason: 'voice_session_registered',
      );
    }
    _activeVoiceSession = VoiceRuntimeSession(
      token: _sessionToken,
      ownerId: ownerId,
      routeId: routeId ?? _activeRouteContext?.routeId,
      shouldRecover: shouldRecover,
      recover: recover,
      isAlivePredicate: isAlive,
      metadata: metadata,
    );
    notifyListeners();
    return _sessionToken;
  }

  bool isVoiceSessionActive({required String ownerId, required int token}) {
    _clearStaleVoiceSession();
    final session = _activeVoiceSession;
    return session != null &&
        session.ownerId == ownerId &&
        session.token == token;
  }

  bool canRecoverVoiceSession({required String ownerId, required int token}) {
    if (!isVoiceSessionActive(ownerId: ownerId, token: token)) {
      return false;
    }
    return _activeVoiceSession?.shouldRecover() ?? false;
  }

  Future<bool> recoverVoiceSession({
    required String ownerId,
    required int token,
  }) async {
    if (!canRecoverVoiceSession(ownerId: ownerId, token: token)) {
      return false;
    }
    await _activeVoiceSession!.recover();
    return true;
  }

  void clearVoiceSession({String? ownerId, int? token}) {
    final session = _activeVoiceSession;
    if (session == null) {
      return;
    }
    if (ownerId != null && session.ownerId != ownerId) {
      return;
    }
    if (token != null && session.token != token) {
      return;
    }
    _clearVoiceSession();
    revokeOwnership(ownerId: ownerId, reason: 'voice_session_cleared');
    notifyListeners();
  }

  void _clearStaleVoiceSession() {
    final session = _activeVoiceSession;
    if (session == null || session.isAlive()) {
      return;
    }
    _clearVoiceSession();
  }

  void _clearVoiceSession() {
    _activeVoiceSession = null;
  }

  void _handleOwnershipRequested(VoiceOwnershipRequestedEvent event) {
    final requesterId = event.metadata['requesterId'];
    if (requesterId is! String || requesterId.isEmpty) {
      return;
    }

    if (!_ownership.isOwned || _ownership.ownerId == requesterId) {
      _grantOwnership(
        ownerId: requesterId,
        source: 'runtime_registry',
        reason: event.reason ?? 'ownership_requested',
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: {'requestSource': event.source},
      );
      return;
    }

    eventBus.publish(
      VoiceOwnershipRejectedEvent(
        source: 'runtime_registry',
        requesterId: requesterId,
        activeOwnerId: _ownership.ownerId,
        reason: 'ownership_conflict',
        correlationId: event.correlationId,
        causationId: event.id,
      ),
    );
  }

  void _grantOwnership({
    required String ownerId,
    required String source,
    String? reason,
    String? correlationId,
    String? causationId,
    Map<String, Object?> metadata = const {},
  }) {
    _ownership = RuntimeOwnership(
      ownerId: ownerId,
      grantedAt: DateTime.now(),
      reason: reason,
      correlationId: correlationId,
    );
    _activeOwnerId = ownerId;
    eventBus.publish(
      VoiceOwnershipGrantedEvent(
        source: source,
        ownerId: ownerId,
        reason: reason,
        correlationId: correlationId,
        causationId: causationId,
        metadata: metadata,
      ),
    );
    notifyListeners();
  }

  bool _isTrustedRuntimeSource(String source) {
    return source == 'runtime_engine' ||
        source == 'voice_session_manager' ||
        source == 'runtime_registry';
  }

  void resetForTesting() {
    _activeOwnerId = null;
    _ownership = const RuntimeOwnership.none();
    _activeRouteContext = null;
    _activeVoiceSession = null;
    _sessionToken = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_ownershipRequestSubscription.cancel());
    super.dispose();
  }
}

class RuntimeOwnership {
  const RuntimeOwnership({
    required this.ownerId,
    required this.grantedAt,
    this.reason,
    this.correlationId,
  });

  const RuntimeOwnership.none()
    : ownerId = null,
      grantedAt = null,
      reason = null,
      correlationId = null;

  final String? ownerId;
  final DateTime? grantedAt;
  final String? reason;
  final String? correlationId;

  bool get isOwned => ownerId != null;
}

class VoiceRuntimeRouteContext {
  const VoiceRuntimeRouteContext({
    required this.routeId,
    this.routeName,
    this.metadata = const {},
  });

  final String routeId;
  final String? routeName;
  final Map<String, Object?> metadata;
}

class VoiceRuntimeSession {
  const VoiceRuntimeSession({
    required this.token,
    required this.ownerId,
    required this.shouldRecover,
    required this.recover,
    this.isAlivePredicate,
    this.routeId,
    this.metadata = const {},
  });

  final int token;
  final String ownerId;
  final String? routeId;
  final VoiceRuntimePredicate shouldRecover;
  final VoiceRuntimeRecoverAction recover;
  final VoiceRuntimePredicate? isAlivePredicate;
  final Map<String, Object?> metadata;

  bool isAlive() => isAlivePredicate?.call() ?? true;
}
