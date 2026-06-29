import 'dart:async';

import 'package:app_voz/features/editor/services/audio_player_service.dart';
import 'package:app_voz/features/recordings/pages/detalhes_gravacao_page.dart';
import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_confirmation_controller.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  testWidgets('detalhes mostra arquivo amigavel sem path interno', (
    tester,
  ) async {
    final playerService = _FakeAudioPlayerService();
    addTearDown(playerService.close);

    await tester.pumpWidget(
      MaterialApp(
        home: DetalhesGravacaoPage(
          usuario: _usuario,
          gravacaoId: 1,
          recordingService: _FakeRecordingManagementService(
            details: _details(
              path:
                  '/data/user/0/br.com.assistentemusical.appvoz/app_flutter/gravacao_123.m4a',
            ),
          ),
          playerService: playerService,
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('/data/user/0'), findsNothing);
    expect(find.textContaining('app_flutter'), findsNothing);
    expect(find.text('Gravação local'), findsOneWidget);
    expect(find.text('gravacao_123.m4a'), findsOneWidget);
  });

  testWidgets('play e stop nos detalhes funcionam com um clique', (
    tester,
  ) async {
    final playerService = _FakeAudioPlayerService();
    addTearDown(playerService.close);
    var suspended = 0;
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DetalhesGravacaoPage(
          usuario: _usuario,
          gravacaoId: 1,
          recordingService: _FakeRecordingManagementService(
            details: _details(path: '/tmp/gravacao_123.m4a'),
          ),
          playerService: playerService,
          enableVoiceListening: false,
          onVoicePlaybackSuspendedForTesting: () => suspended++,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Tocar'));
    await tester.pump();

    expect(playerService.playedPaths, ['/tmp/gravacao_123.m4a']);
    expect(find.widgetWithText(FilledButton, 'Parar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Parar'));
    await tester.pump();

    expect(playerService.stopCalls, 1);
    expect(suspended, 1);
    expect(resumed, 1);
    expect(find.widgetWithText(FilledButton, 'Tocar'), findsOneWidget);
  });

  testWidgets('completed nos detalhes solicita retomada da escuta', (
    tester,
  ) async {
    final playerService = _FakeAudioPlayerService();
    addTearDown(playerService.close);
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DetalhesGravacaoPage(
          usuario: _usuario,
          gravacaoId: 1,
          recordingService: _FakeRecordingManagementService(
            details: _details(path: '/tmp/gravacao_123.m4a'),
          ),
          playerService: playerService,
          enableVoiceListening: false,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Tocar'));
    await tester.pump();
    playerService.emitCompleted();
    await tester.pump();

    expect(resumed, 1);
    expect(find.widgetWithText(FilledButton, 'Tocar'), findsOneWidget);
  });

  testWidgets('erro nos detalhes solicita retomada da escuta', (tester) async {
    final playerService = _FakeAudioPlayerService()..throwOnPlay = true;
    addTearDown(playerService.close);
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DetalhesGravacaoPage(
          usuario: _usuario,
          gravacaoId: 1,
          recordingService: _FakeRecordingManagementService(
            details: _details(path: '/tmp/gravacao_123.m4a'),
          ),
          playerService: playerService,
          enableVoiceListening: false,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Tocar'));
    await tester.pump();

    expect(resumed, 1);
    expect(find.widgetWithText(FilledButton, 'Tocar'), findsOneWidget);
  });

  testWidgets(
    'renomear para guitarra nos detalhes abre modal pre-preenchido',
    (tester) async {
      final playerService = _FakeAudioPlayerService();
      addTearDown(playerService.close);
      final service = _FakeRecordingManagementService(
        details: _details(path: '/tmp/gravacao_123.m4a'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DetalhesGravacaoPage(
            usuario: _usuario,
            gravacaoId: 1,
            recordingService: service,
            playerService: playerService,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state =
          tester.state(find.byType(DetalhesGravacaoPage)) as dynamic;

      final resultFuture = (state.debugHandleVoiceCommandForTesting(
            'renomear para guitarra',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget,
          reason: 'Modal de renomeação deve abrir');
      expect(find.text('guitarra'), findsOneWidget,
          reason: 'Campo deve estar pré-preenchido com o novo nome');

      // Confirma por voz via VoiceConfirmationController
      expect(
        (state.voiceConfirmationController as VoiceConfirmationController)
            .hasPendingConfirmation,
        isTrue,
        reason: 'Confirmação por voz deve estar pendente enquanto modal estiver aberto',
      );

      // Toca Cancelar para fechar sem salvar (evita DB call)
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await resultFuture;

      expect(service.renamedCalls, isEmpty,
          reason: 'Cancelar não deve salvar');
    },
  );

  testWidgets(
    'renomear nos detalhes nao salva direto sem confirmacao no modal',
    (tester) async {
      final playerService = _FakeAudioPlayerService();
      addTearDown(playerService.close);
      final service = _FakeRecordingManagementService(
        details: _details(path: '/tmp/gravacao_123.m4a'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DetalhesGravacaoPage(
            usuario: _usuario,
            gravacaoId: 1,
            recordingService: service,
            playerService: playerService,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state =
          tester.state(find.byType(DetalhesGravacaoPage)) as dynamic;

      final resultFuture = (state.debugHandleVoiceCommandForTesting(
            'renomear para guitarra',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      // Modal está aberto — cancela por voz
      await (state.voiceConfirmationController as VoiceConfirmationController)
          .handle(const CommandResult(
        originalText: 'cancelar',
        normalizedText: 'cancelar',
        type: VoiceCommandType.cancelarAcao,
        recognized: true,
        tipoComando: 'cancelarAcao',
      ));
      await tester.pumpAndSettle();
      final result = await resultFuture;

      expect(result.handled, isTrue);
      expect(service.renamedCalls, isEmpty,
          reason: 'Cancelar por voz não deve renomear');
    },
  );

  testWidgets(
    'frase incompleta renomear nos detalhes nao abre modal nem salva',
    (tester) async {
      final playerService = _FakeAudioPlayerService();
      addTearDown(playerService.close);
      final service = _FakeRecordingManagementService(
        details: _details(path: '/tmp/gravacao_123.m4a'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DetalhesGravacaoPage(
            usuario: _usuario,
            gravacaoId: 1,
            recordingService: service,
            playerService: playerService,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state =
          tester.state(find.byType(DetalhesGravacaoPage)) as dynamic;

      final result = await (state.debugHandleVoiceCommandForTesting(
            'renomear gravacao',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear gravação'), findsNothing,
          reason: 'Frase incompleta não deve abrir modal');
      expect(result.handled, isTrue);
      expect(result.restartListening, isTrue,
          reason: 'STT deve reiniciar para aguardar continuação');
      expect(service.renamedCalls, isEmpty);
    },
  );
}

final _usuario = Usuario(
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

RecordingDetails _details({required String path}) {
  final gravacao = Gravacao(
    usuarioId: 1,
    nome: 'Ideia',
    caminhoArquivo: path,
    dataCriacao: '2026-06-15T10:00:00.000',
    duracaoSegundos: 3,
    tamanhoBytes: 128,
  );

  return RecordingDetails(
    gravacao: gravacao,
    fileInfo: RecordingFileInfo(exists: true, sizeBytes: 128, path: path),
  );
}

class _FakeRecordingManagementService extends RecordingManagementService {
  _FakeRecordingManagementService({required this.details});

  final RecordingDetails details;
  final renamedCalls = <(int, String)>[];

  @override
  Future<RecordingDetails?> loadDetails(int gravacaoId) async => details;

  @override
  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    return [details.gravacao];
  }

  @override
  Future<List<Gravacao>> listByProjectWithFileState(
    int projetoId, {
    String? termoBusca,
    String? status,
  }) async {
    return [details.gravacao];
  }

  @override
  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String novoNome,
    required List<Gravacao> gravacoesRelacionadas,
  }) async {
    renamedCalls.add((gravacao.id ?? -1, novoNome));
    return gravacao.copyWith(nome: novoNome);
  }
}

class _FakeAudioPlayerService implements AudioPlayerService {
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final playedPaths = <String>[];
  var playing = false;
  var stopCalls = 0;
  var throwOnPlay = false;

  @override
  String? currentPath;

  @override
  bool get isPlaying => playing;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> play(String path) async {
    if (throwOnPlay) {
      throw StateError('player failure');
    }

    currentPath = path;
    playedPaths.add(path);
    playing = true;
    _playerStateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  void emitCompleted() {
    playing = false;
    _playerStateController.add(PlayerState(false, ProcessingState.completed));
  }

  @override
  Future<void> dispose() async {}

  void close() {
    _playerStateController.close();
    _positionController.close();
    _durationController.close();
  }
}
