import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../nlu/voice_intent.dart';
import '../voice_realtime_event_bus.dart';
import '../voice_realtime_events.dart';
import '../../../editor/services/audio_player_service.dart';
import '../../../recordings/services/recording_management_service.dart';
import '../../coordination/voice_session_manager.dart';
import 'adapters/app_recording_context_resolver.dart';
import 'adapters/audio_player_playback_service.dart';
import 'contratos/audio_output_guard.dart';
import 'contracts/voice_session_context_holder.dart';
import 'handlers/metronome_command_handler.dart';
import 'handlers/playback_command_handler.dart';
import 'handlers/recording_management_command_handler.dart';
import 'handlers/track_command_handler.dart';
import 'voice_command_handler.dart';

class VoiceCommandDispatcher {
  VoiceCommandDispatcher({
    VoiceRealtimeEventBus? eventBus,
    VoiceSessionContextHolder? contextHolder,
    String? Function()? activeSessionTokenProvider,
    Map<Type, VoiceCommandHandler<dynamic>>? handlers,
    this.processedHistoryLimit = 100,
    this.pendingTransactionTimeout = const Duration(seconds: 30),
  }) : assert(processedHistoryLimit > 0),
       assert(!pendingTransactionTimeout.isNegative),
       eventBus = eventBus ?? VoiceRealtimeEventBus.instance,
       _handlers =
           handlers ??
           _defaultHandlers(
             eventBus ?? VoiceRealtimeEventBus.instance,
             contextHolder ?? VoiceSessionContextHolder(),
             activeSessionTokenProvider,
           );

  static final VoiceCommandDispatcher instance = VoiceCommandDispatcher();

  final VoiceRealtimeEventBus eventBus;
  final int processedHistoryLimit;
  final Duration pendingTransactionTimeout;
  final Map<Type, VoiceCommandHandler<dynamic>> _handlers;
  final Set<String> _processedCorrelationIds = {};
  final Queue<String> _processedCorrelationOrder = Queue<String>();

  StreamSubscription<VoiceCommandInterpretedEvent>? _subscription;
  StreamSubscription<VoiceCommandConfirmationRequiredEvent>?
  _confirmationSubscription;
  Future<void> _lastCommand = Future<void>.value();
  _PendingTransaction? _pendingTransaction;
  Timer? _pendingTransactionTimer;
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
    _confirmationSubscription = eventBus
        .on<VoiceCommandConfirmationRequiredEvent>()
        .listen(_rememberPendingTransaction);
    _started = true;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _confirmationSubscription?.cancel();
    _subscription = null;
    _confirmationSubscription = null;
    clearPendingTransaction(reason: 'dispatcher_disposed');
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
    if (intent is ConfirmIntent || intent is CancelIntent) {
      await _dispatchConfirmationVerdict(event);
      return;
    }

    if (intent is UnknownIntent) {
      _publishIgnored(
        event,
        reason: 'unknown_intent_ignored',
        message:
            'Comando não reconhecido recebido para o ID de correlação ${event.correlationId}.',
        metadata: {
          'intentType': intent.runtimeType.toString(),
          'rawText': intent.rawText,
          'executed': false,
        },
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

    final activeTransaction = _pendingTransaction;
    if (activeTransaction != null &&
        handler is ConfirmableVoiceCommandHandler) {
      _publishTransactionConflict(
        intent: intent,
        rejectedCorrelationId: event.correlationId,
        causationId: event.id,
        activeTransaction: activeTransaction,
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
      if (error is! VoiceCommandHandlerException ||
          !error.failureEventPublished) {
        eventBus.publish(
          VoiceCommandFailedEvent(
            source: 'voice_command_dispatcher',
            reason: 'command_handler_failed',
            correlationId: event.correlationId,
            causationId: event.id,
            intent: intent,
            metadata: {'error': error.toString()},
          ),
        );
      }
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

  Future<void> _dispatchConfirmationVerdict(
    VoiceCommandInterpretedEvent event,
  ) async {
    final transaction = _pendingTransaction;
    if (transaction == null) {
      _publishIgnored(
        event,
        reason: 'orphan_confirmation_ignored',
        metadata: {'intentType': event.intent.runtimeType.toString()},
      );
      return;
    }

    if (_pendingTransaction?.correlationId != transaction.correlationId) {
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_command_dispatcher',
          reason: 'confirmation_transaction_mismatch',
          correlationId: event.correlationId,
          causationId: event.id,
          metadata: {
            'expectedCorrelationId': transaction.correlationId,
            'activeCorrelationId': _pendingTransaction?.correlationId,
            'intentType': transaction.intent.runtimeType.toString(),
          },
        ),
      );
      return;
    }

    final originalIntent = transaction.intent;
    final handler = _handlers[originalIntent.runtimeType];
    if (handler is! ConfirmableVoiceCommandHandler) {
      _pendingTransaction = null;
      _pendingTransactionTimer?.cancel();
      _pendingTransactionTimer = null;
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_command_dispatcher',
          reason: 'confirmation_handler_not_confirmable',
          correlationId: transaction.correlationId,
          causationId: event.id,
          metadata: {'intentType': originalIntent.runtimeType.toString()},
        ),
      );
      return;
    }

    _pendingTransaction = null;
    _pendingTransactionTimer?.cancel();
    _pendingTransactionTimer = null;

    final approved = event.intent is ConfirmIntent;
    try {
      await handler.handleConfirmation(
        originalIntent,
        approved,
        transaction.correlationId,
      );
      eventBus.publish(
        VoiceStateChangedEvent(
          source: 'voice_command_dispatcher',
          previousState: 'confirmationPending',
          nextState: approved
              ? 'confirmationApproved'
              : 'confirmationCancelled',
          reason: approved
              ? 'pending_transaction_confirmed'
              : 'pending_transaction_cancelled',
          correlationId: transaction.correlationId,
          causationId: event.id,
          metadata: {
            'verdictCorrelationId': event.correlationId,
            'intentType': originalIntent.runtimeType.toString(),
          },
        ),
      );
    } catch (error) {
      if (error is! VoiceCommandHandlerException ||
          !error.failureEventPublished) {
        eventBus.publish(
          VoiceCommandFailedEvent(
            source: 'voice_command_dispatcher',
            reason: 'confirmation_handler_failed',
            correlationId: transaction.correlationId,
            causationId: event.id,
            intent: originalIntent,
            metadata: {'error': error.toString()},
          ),
        );
      }
      eventBus.publish(
        VoiceSystemDegradedEvent(
          source: 'voice_command_dispatcher',
          reason: 'confirmation_handler_failed',
          correlationId: transaction.correlationId,
          causationId: event.id,
          metadata: {
            'error': error.toString(),
            'intentType': originalIntent.runtimeType.toString(),
          },
        ),
      );
    }
  }

  void _rememberPendingTransaction(
    VoiceCommandConfirmationRequiredEvent event,
  ) {
    final activeTransaction = _pendingTransaction;
    if (activeTransaction != null) {
      _publishTransactionConflict(
        intent: event.intent,
        rejectedCorrelationId: event.correlationId,
        causationId: event.id,
        activeTransaction: activeTransaction,
      );
      return;
    }

    _pendingTransactionTimer?.cancel();
    _pendingTransaction = _PendingTransaction(
      intent: event.intent,
      correlationId: event.correlationId,
    );
    if (pendingTransactionTimeout == Duration.zero) {
      clearPendingTransaction(reason: 'pending_transaction_timeout');
      return;
    }
    _pendingTransactionTimer = Timer(
      pendingTransactionTimeout,
      () => clearPendingTransaction(reason: 'pending_transaction_timeout'),
    );
  }

  void clearPendingTransaction({required String reason}) {
    final transaction = _pendingTransaction;
    _pendingTransaction = null;
    _pendingTransactionTimer?.cancel();
    _pendingTransactionTimer = null;
    if (transaction == null) {
      return;
    }
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_command_dispatcher',
        previousState: 'confirmationPending',
        nextState: 'confirmationDiscarded',
        reason: reason,
        correlationId: transaction.correlationId,
        metadata: {'intentType': transaction.intent.runtimeType.toString()},
      ),
    );
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
    String? message,
    Map<String, Object?> metadata = const {},
  }) {
    eventBus.publish(
      VoiceStateChangedEvent(
        source: 'voice_command_dispatcher',
        previousState: 'commandQueued',
        nextState: 'commandIgnored',
        reason: reason,
        message: message,
        correlationId: event.correlationId,
        causationId: event.id,
        metadata: metadata,
      ),
    );
  }

  void _publishTransactionConflict({
    required VoiceIntent intent,
    required String rejectedCorrelationId,
    required String causationId,
    required _PendingTransaction activeTransaction,
  }) {
    final metadata = {
      'rejectedIntentType': intent.runtimeType.toString(),
      'activeIntentType': activeTransaction.intent.runtimeType.toString(),
      'activeCorrelationId': activeTransaction.correlationId,
      'conflictPolicy': 'single_pending_transaction',
    };
    eventBus.publish(
      VoiceCommandFailedEvent(
        source: 'voice_command_dispatcher',
        reason: 'transaction_conflict_active',
        correlationId: rejectedCorrelationId,
        causationId: causationId,
        intent: intent,
        metadata: metadata,
      ),
    );
    eventBus.publish(
      VoiceSystemDegradedEvent(
        source: 'voice_command_dispatcher',
        reason: 'transaction_conflict_active',
        correlationId: rejectedCorrelationId,
        causationId: causationId,
        metadata: metadata,
      ),
    );
  }

  static Map<Type, VoiceCommandHandler<dynamic>> _defaultHandlers(
    VoiceRealtimeEventBus eventBus,
    VoiceSessionContextHolder contextHolder,
    String? Function()? activeSessionTokenProvider,
  ) {
    final recordingService = RecordingManagementService();
    final recordingManagementHandler = RecordingManagementCommandHandler(
      recordingService: recordingService,
      recordingContextResolver: AppRecordingContextResolver(
        recordingService: recordingService,
        contextHolder: contextHolder,
        activeSessionTokenProvider:
            activeSessionTokenProvider ??
            () => contextHolder.activeSessionToken,
      ),
      eventBus: eventBus,
    );

    return {
      MetronomeIntent: MetronomeCommandHandler(
        service: StubMetronomeService(),
        eventBus: eventBus,
      ),
      PlaybackIntent: PlaybackCommandHandler(
        service: LazyAudioPlayerPlaybackService(
          playerServiceFactory: AudioPlayerService.new,
        ),
        audioOutputGuard: LazyAudioOutputGuard(
          () => VoiceSessionManager.instance,
        ),
        eventBus: eventBus,
      ),
      TrackIntent: TrackCommandHandler(
        service: StubTrackService(),
        eventBus: eventBus,
      ),
      DeleteLastRecordingIntent: recordingManagementHandler,
      RenameLastRecordingIntent: recordingManagementHandler,
    };
  }
}

class _PendingTransaction {
  const _PendingTransaction({
    required this.intent,
    required this.correlationId,
  });

  final VoiceIntent intent;
  final String correlationId;
}
