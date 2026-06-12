import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/features/voices/realtime/dispatch/adapters/app_recording_context_resolver.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contracts/voice_session_context_holder.dart';
import 'package:app_voz/features/voices/realtime/dispatch/contracts/voice_recording_context_resolver.dart';
import 'package:app_voz/features/voices/realtime/dispatch/handlers/recording_management_command_handler.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent.dart';
import 'package:app_voz/features/voices/realtime/nlu/voice_intent_parser.dart';
import 'package:app_voz/features/voices/realtime/tts/intent_response_formatter.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_event_bus.dart';
import 'package:app_voz/features/voices/realtime/voice_realtime_events.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordingManagementCommandHandler', () {
    late VoiceRealtimeEventBus bus;
    late _FakeRecordingManagementService recordingService;
    late _FakeVoiceRecordingContextResolver contextResolver;
    late RecordingManagementCommandHandler handler;

    setUp(() {
      bus = VoiceRealtimeEventBus();
      recordingService = _FakeRecordingManagementService();
      contextResolver = _FakeVoiceRecordingContextResolver(
        recordingService.recordings.first,
      );
      handler = RecordingManagementCommandHandler(
        recordingService: recordingService,
        recordingContextResolver: contextResolver,
        eventBus: bus,
      );
    });

    test(
      'deletar gravacao ativa parser e exige confirmacao sem excluir',
      () async {
        final intent = const VoiceIntentParser().parse('deletar gravação');
        expect(intent, isA<DeleteLastRecordingIntent>());

        await handler.handle(intent, 'delete-flow');

        expect(recordingService.deleteCalls, isEmpty);
        final confirmation = bus.timeline
            .whereType<VoiceCommandConfirmationRequiredEvent>()
            .single;
        expect(confirmation.correlationId, 'delete-flow');
        expect(confirmation.action, 'delete_last_recording');
        expect(confirmation.intent, isA<DeleteLastRecordingIntent>());
      },
    );

    test(
      'confirmacao positiva exclui a gravacao retornada pelo resolver',
      () async {
        final target = contextResolver.recording!;

        await handler.handle(
          const DeleteLastRecordingIntent(rawText: 'deletar ultima gravacao'),
          'delete-confirm-flow',
        );
        await handler.handleConfirmation(
          const DeleteLastRecordingIntent(rawText: 'deletar ultima gravacao'),
          true,
          'delete-confirm-flow',
        );

        expect(recordingService.deleteCalls, hasLength(1));
        expect(identical(recordingService.deleteCalls.single, target), isTrue);
      },
    );

    test(
      'renomear extrai novo nome e repassa assinatura real ao servico',
      () async {
        final intent = const VoiceIntentParser().parse(
          'renomear última gravação para riff principal',
        );
        expect(intent, isA<RenameLastRecordingIntent>());
        expect((intent as RenameLastRecordingIntent).newName, 'riff principal');

        await handler.handle(intent, 'rename-flow');

        expect(recordingService.renameCalls, hasLength(1));
        expect(
          identical(
            recordingService.renameCalls.single.gravacao,
            contextResolver.recording,
          ),
          isTrue,
        );
        expect(recordingService.renameCalls.single.gravacao.id, 1);
        expect(recordingService.renameCalls.single.novoNome, 'riff principal');
        expect(recordingService.renameCalls.single.relacionadas, hasLength(2));
        final handled = bus.timeline
            .whereType<VoiceStateChangedEvent>()
            .where((event) => event.reason == 'recording_renamed')
            .single;
        expect(handled.correlationId, 'rename-flow');
      },
    );

    test(
      'falha de banco gera VoiceCommandFailedEvent sem crash externo',
      () async {
        recordingService.failRename = true;
        final intent = const RenameLastRecordingIntent(
          newName: 'take novo',
          rawText: 'renomear ultima gravacao para take novo',
        );

        await expectLater(
          handler.handle(intent, 'database-flow'),
          throwsA(isA<Exception>()),
        );

        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.reason, 'database_error');
        expect(failed.correlationId, 'database-flow');
        expect(
          const IntentResponseFormatter().formatFailure('database_error'),
          'Nao foi possivel salvar essa alteracao agora.',
        );
      },
    );

    test(
      'sem ultima gravacao resolvivel publica recording_context_missing',
      () async {
        contextResolver.recording = null;
        final intent = const RenameLastRecordingIntent(
          newName: 'take novo',
          rawText: 'renomear ultima gravacao para take novo',
        );

        await expectLater(
          handler.handle(intent, 'missing-flow'),
          throwsA(isA<Exception>()),
        );

        expect(recordingService.renameCalls, isEmpty);
        expect(recordingService.deleteCalls, isEmpty);
        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.reason, 'recording_context_missing');
        expect(failed.correlationId, 'missing-flow');
      },
    );
  });

  group('AppRecordingContextResolver', () {
    test('resolve ultima gravacao pelo projeto ativo do holder', () async {
      final recordingService = _FakeRecordingManagementService();
      final contextHolder = VoiceSessionContextHolder()
        ..updateActiveContext(
          projectId: '9',
          userId: '7',
          sessionToken: 'active-token',
        );

      final resolver = AppRecordingContextResolver(
        recordingService: recordingService,
        contextHolder: contextHolder,
        activeSessionTokenProvider: () => 'active-token',
      );

      final resolved = await resolver.resolveLastRecording();

      expect(resolved?.id, recordingService.recordings.first.id);
      expect(recordingService.projectQueries, [9]);
      expect(recordingService.userQueries, isEmpty);
    });

    test('retorna null quando o editor limpa o projeto ativo', () async {
      final recordingService = _FakeRecordingManagementService();
      final contextHolder = VoiceSessionContextHolder()
        ..updateActiveContext(
          projectId: '9',
          userId: '7',
          sessionToken: 'active-token',
        )
        ..clearActiveContext();
      final resolver = AppRecordingContextResolver(
        recordingService: recordingService,
        contextHolder: contextHolder,
        activeSessionTokenProvider: () => 'active-token',
      );

      expect(await resolver.resolveLastRecording(), isNull);
      expect(recordingService.projectQueries, isEmpty);
      expect(recordingService.userQueries, isEmpty);
    });

    test('retorna null para id de projeto corrompido', () async {
      final recordingService = _FakeRecordingManagementService();
      final contextHolder = VoiceSessionContextHolder()
        ..updateActiveContext(
          projectId: 'projeto-quebrado',
          userId: '7',
          sessionToken: 'active-token',
        );
      final resolver = AppRecordingContextResolver(
        recordingService: recordingService,
        contextHolder: contextHolder,
        activeSessionTokenProvider: () => 'active-token',
      );

      expect(await resolver.resolveLastRecording(), isNull);
      expect(recordingService.projectQueries, isEmpty);
    });

    test(
      'retorna null quando token do holder nao corresponde a sessao ativa',
      () async {
        final recordingService = _FakeRecordingManagementService();
        final contextHolder = VoiceSessionContextHolder()
          ..updateActiveContext(
            projectId: '9',
            userId: '7',
            sessionToken: 'stale-token',
          );
        final resolver = AppRecordingContextResolver(
          recordingService: recordingService,
          contextHolder: contextHolder,
          activeSessionTokenProvider: () => 'active-token',
        );

        expect(await resolver.resolveLastRecording(), isNull);
        expect(recordingService.projectQueries, isEmpty);
        expect(recordingService.userQueries, isEmpty);
      },
    );

    test(
      'retorna null quando sessao ativa nao possui token confiavel',
      () async {
        final recordingService = _FakeRecordingManagementService();
        final contextHolder = VoiceSessionContextHolder()
          ..updateActiveContext(
            projectId: '9',
            userId: '7',
            sessionToken: 'stale-token',
          );
        final resolver = AppRecordingContextResolver(
          recordingService: recordingService,
          contextHolder: contextHolder,
          activeSessionTokenProvider: () => null,
        );

        expect(await resolver.resolveLastRecording(), isNull);
        expect(recordingService.projectQueries, isEmpty);
        expect(recordingService.userQueries, isEmpty);
      },
    );

    test(
      'limpeza do holder faz handler abortar com contexto ausente',
      () async {
        final bus = VoiceRealtimeEventBus();
        final recordingService = _FakeRecordingManagementService();
        final contextHolder = VoiceSessionContextHolder()
          ..updateActiveContext(
            projectId: '9',
            userId: '7',
            sessionToken: 'active-token',
          );
        final resolver = AppRecordingContextResolver(
          recordingService: recordingService,
          contextHolder: contextHolder,
          activeSessionTokenProvider: () => 'active-token',
        );
        final handler = RecordingManagementCommandHandler(
          recordingService: recordingService,
          recordingContextResolver: resolver,
          eventBus: bus,
        );
        contextHolder.clearActiveContext();

        await expectLater(
          handler.handle(
            const DeleteLastRecordingIntent(rawText: 'deletar ultima gravacao'),
            'cleared-context-flow',
          ),
          throwsA(isA<Exception>()),
        );

        final failed = bus.timeline.whereType<VoiceCommandFailedEvent>().single;
        expect(failed.reason, 'recording_context_missing');
        expect(failed.correlationId, 'cleared-context-flow');
      },
    );
  });
}

class _FakeVoiceRecordingContextResolver
    implements VoiceRecordingContextResolver {
  _FakeVoiceRecordingContextResolver(this.recording);

  Gravacao? recording;

  @override
  Future<Gravacao?> resolveLastRecording() async => recording;
}

class _FakeRecordingManagementService extends RecordingManagementService {
  _FakeRecordingManagementService();

  final recordings = [
    Gravacao(
      id: 1,
      usuarioId: 7,
      projetoId: 9,
      nome: 'Take recente',
      caminhoArquivo: 'recente.m4a',
      dataCriacao: DateTime(2026, 5, 24, 10).toIso8601String(),
    ),
    Gravacao(
      id: 2,
      usuarioId: 7,
      projetoId: 9,
      nome: 'Take antigo',
      caminhoArquivo: 'antigo.m4a',
      dataCriacao: DateTime(2026, 5, 23, 10).toIso8601String(),
    ),
  ];
  final List<_RenameCall> renameCalls = [];
  final List<Gravacao> deleteCalls = [];
  final List<int> projectQueries = [];
  final List<int> userQueries = [];
  var failRename = false;

  @override
  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    userQueries.add(usuarioId);
    return recordings
        .where((recording) => recording.usuarioId == usuarioId)
        .toList();
  }

  @override
  Future<List<Gravacao>> listByProjectWithFileState(
    int projetoId, {
    String? termoBusca,
    String? status,
  }) async {
    projectQueries.add(projetoId);
    return recordings
        .where((recording) => recording.projetoId == projetoId)
        .toList();
  }

  @override
  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String novoNome,
    required List<Gravacao> gravacoesRelacionadas,
  }) async {
    if (failRename) {
      throw StateError('database unavailable');
    }
    renameCalls.add(
      _RenameCall(
        gravacao: gravacao,
        novoNome: novoNome,
        relacionadas: gravacoesRelacionadas,
      ),
    );
    return gravacao.copyWith(nome: novoNome);
  }

  @override
  Future<void> deleteRecording(Gravacao gravacao) async {
    deleteCalls.add(gravacao);
  }
}

class _RenameCall {
  const _RenameCall({
    required this.gravacao,
    required this.novoNome,
    required this.relacionadas,
  });

  final Gravacao gravacao;
  final String novoNome;
  final List<Gravacao> relacionadas;
}
