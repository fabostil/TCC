import '../../../../../models/gravacao.dart';
import '../../../../recordings/services/recording_management_service.dart';
import '../contracts/voice_recording_context_resolver.dart';
import '../../nlu/voice_intent.dart';
import '../../voice_realtime_event_bus.dart';
import '../../voice_realtime_events.dart';
import '../voice_command_handler.dart';

class RecordingManagementCommandHandler
    implements ConfirmableVoiceCommandHandler<VoiceIntent> {
  RecordingManagementCommandHandler({
    required RecordingManagementService recordingService,
    VoiceRecordingContextResolver? recordingContextResolver,
    VoiceRealtimeEventBus? eventBus,
  }) : _recordingService = recordingService,
       _recordingContextResolver =
           recordingContextResolver ??
           const StubVoiceRecordingContextResolver(),
       _eventBus = eventBus ?? VoiceRealtimeEventBus.instance;

  final RecordingManagementService _recordingService;
  final VoiceRecordingContextResolver _recordingContextResolver;
  final VoiceRealtimeEventBus _eventBus;
  final Map<String, Gravacao> _pendingDeleteByCorrelation = {};

  @override
  Future<void> handle(VoiceIntent intent, String correlationId) async {
    switch (intent) {
      case DeleteLastRecordingIntent():
        await _handleDelete(intent, correlationId);
      case RenameLastRecordingIntent():
        await _handleRename(intent, correlationId);
      default:
        throw ArgumentError.value(intent.runtimeType, 'intent');
    }
  }

  @override
  Future<void> handleConfirmation(
    VoiceIntent intent,
    bool approved,
    String correlationId,
  ) async {
    switch (intent) {
      case DeleteLastRecordingIntent():
        await _handleDeleteConfirmation(intent, approved, correlationId);
      default:
        throw ArgumentError.value(intent.runtimeType, 'intent');
    }
  }

  Future<void> _handleDelete(
    DeleteLastRecordingIntent intent,
    String correlationId,
  ) async {
    final latest = await _resolveLatestRecording(intent, correlationId);
    if (latest == null) {
      return;
    }

    _pendingDeleteByCorrelation[correlationId] = latest;
    _eventBus.publish(
      VoiceCommandConfirmationRequiredEvent(
        source: 'recording_management_command_handler',
        action: 'delete_last_recording',
        intent: intent,
        correlationId: correlationId,
        metadata: {'recordingId': latest.id, 'recordingName': latest.nome},
      ),
    );
  }

  Future<void> _handleDeleteConfirmation(
    DeleteLastRecordingIntent intent,
    bool approved,
    String correlationId,
  ) async {
    final pending = _pendingDeleteByCorrelation.remove(correlationId);
    if (pending == null) {
      _publishFailure(
        intent: intent,
        correlationId: correlationId,
        reason: 'recording_context_missing',
      );
      throw VoiceCommandHandlerException(
        reason: 'recording_context_missing',
        cause: StateError('recording_context_missing'),
        failureEventPublished: true,
      );
    }

    if (!approved) {
      _eventBus.publish(
        VoiceCommandConfirmationResolvedEvent(
          source: 'recording_management_command_handler',
          action: 'delete_last_recording',
          intent: intent,
          approved: false,
          correlationId: correlationId,
          reason: 'recording_delete_cancelled',
          metadata: {'recordingId': pending.id, 'recordingName': pending.nome},
        ),
      );
      return;
    }

    try {
      await _recordingService.deleteRecording(pending);
      _eventBus.publish(
        VoiceCommandConfirmationResolvedEvent(
          source: 'recording_management_command_handler',
          action: 'delete_last_recording',
          intent: intent,
          approved: true,
          correlationId: correlationId,
          reason: 'recording_deleted',
          metadata: {'recordingId': pending.id, 'recordingName': pending.nome},
        ),
      );
    } catch (error) {
      _publishFailure(
        intent: intent,
        correlationId: correlationId,
        reason: 'database_error',
        metadata: {'error': error.toString()},
      );
      throw VoiceCommandHandlerException(
        reason: 'database_error',
        cause: error,
        failureEventPublished: true,
      );
    }
  }

  Future<void> _handleRename(
    RenameLastRecordingIntent intent,
    String correlationId,
  ) async {
    final latest = await _resolveLatestRecording(intent, correlationId);
    if (latest == null) {
      return;
    }

    try {
      final related = await _listRelatedRecordings(latest);
      final updated = await _recordingService.renameRecording(
        gravacao: latest,
        novoNome: intent.newName,
        gravacoesRelacionadas: related,
      );
      _eventBus.publish(
        VoiceStateChangedEvent(
          source: 'recording_management_command_handler',
          previousState: 'commandPending',
          nextState: 'commandHandled',
          reason: 'recording_renamed',
          correlationId: correlationId,
          metadata: {'recordingId': updated.id, 'recordingName': updated.nome},
        ),
      );
    } catch (error) {
      if (error is VoiceCommandHandlerException &&
          error.failureEventPublished) {
        rethrow;
      }
      _publishFailure(
        intent: intent,
        correlationId: correlationId,
        reason: 'database_error',
        metadata: {'error': error.toString()},
      );
      throw VoiceCommandHandlerException(
        reason: 'database_error',
        cause: error,
        failureEventPublished: true,
      );
    }
  }

  Future<Gravacao?> _resolveLatestRecording(
    VoiceIntent intent,
    String correlationId,
  ) async {
    try {
      final recording = await _recordingContextResolver.resolveLastRecording();
      if (recording == null) {
        _publishFailure(
          intent: intent,
          correlationId: correlationId,
          reason: 'recording_context_missing',
        );
        throw VoiceCommandHandlerException(
          reason: 'recording_context_missing',
          cause: StateError('recording_context_missing'),
          failureEventPublished: true,
        );
      }

      return recording;
    } catch (error) {
      if (error is VoiceCommandHandlerException &&
          error.failureEventPublished) {
        rethrow;
      }
      _publishFailure(
        intent: intent,
        correlationId: correlationId,
        reason: 'database_error',
        metadata: {'error': error.toString()},
      );
      throw VoiceCommandHandlerException(
        reason: 'database_error',
        cause: error,
        failureEventPublished: true,
      );
    }
  }

  Future<List<Gravacao>> _listRelatedRecordings(Gravacao latest) {
    final projetoId = latest.projetoId;
    if (projetoId != null) {
      return _recordingService.listByProjectWithFileState(projetoId);
    }
    return _recordingService.listByUserWithFileState(latest.usuarioId);
  }

  void _publishFailure({
    required VoiceIntent intent,
    required String correlationId,
    required String reason,
    Map<String, Object?> metadata = const {},
  }) {
    _eventBus.publish(
      VoiceCommandFailedEvent(
        source: 'recording_management_command_handler',
        reason: reason,
        correlationId: correlationId,
        intent: intent,
        metadata: metadata,
      ),
    );
  }
}
