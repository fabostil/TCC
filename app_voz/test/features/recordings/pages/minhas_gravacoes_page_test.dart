import 'dart:async';

import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/recordings/pages/minhas_gravacoes_page.dart';
import 'package:app_voz/features/voices/coordination/voice_confirmation_controller.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  testWidgets('abre e fecha ajuda contextual de gravacoes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuario,
          recordingsController: _RecordingsHelpTestController(),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('recordings_voice_command_help_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('recordings_voice_command_help_button')),
    );
    await tester.pump();

    expect(find.text('Comandos em gravações'), findsOneWidget);
    expect(find.text('Tocar item 1'), findsOneWidget);
    expect(find.text('Excluir gravação'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice_command_help_close_button')));
    await tester.pump();

    expect(find.text('Comandos em gravações'), findsNothing);
  });

  testWidgets('excluir gravacao continua abrindo confirmacao', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuario,
          recordingsController: _RecordingsHelpTestController(
            recordings: [_recording(id: 1, name: 'Ideia')],
          ),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();

    expect(find.text('Excluir gravação'), findsOneWidget);
    expect(
      find.textContaining('Deseja remover "Ideia" do app e do dispositivo?'),
      findsOneWidget,
    );
  });

  testWidgets('cards mostram item visual sem conflitar com titulo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuario,
          recordingsController: _RecordingsHelpTestController(
            recordings: [
              _recording(id: 4, name: 'Gravação 3'),
              _recording(id: 3, name: 'Gravação 2'),
              _recording(id: 2, name: 'Gravação 1'),
            ],
          ),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Gravação 3'), findsOneWidget);
    expect(find.text('Gravação 2'), findsOneWidget);
    expect(find.text('Item 1 da lista'), findsOneWidget);
    expect(find.text('Item 2 da lista'), findsOneWidget);
    expect(find.text('Diga: tocar item 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Item 1 da lista')).dy,
      lessThan(tester.getTopLeft(find.text('Item 2 da lista')).dy),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();

    expect(find.text('Gravação 1'), findsOneWidget);
    expect(find.text('Item 3 da lista'), findsOneWidget);
  });

  testWidgets('referencia parcial por voz toca indice visual atual', (
    tester,
  ) async {
    final controller = _RecordingsHelpTestController(
      recordings: [
        _recording(id: 4, name: 'Gravação 3'),
        _recording(id: 3, name: 'Gravação 2'),
        _recording(id: 2, name: 'Gravação 1'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuarioSemId,
          recordingsController: controller,
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;
    // Bare "gravacao N" is now BLOCKED (waits for full command like
    // "detalhes da gravação 1") — does NOT trigger playback.
    await state.debugHandleRecordingReferenceForTesting('gravação 1');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('item 1');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('item 2');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('primeira gravação');
    await tester.pump();

    // 'gravação 1' → blocked (partial); 'item 1' → id=4; 'item 2' → id=3;
    // 'primeira gravação' → first item = id=4.
    expect(controller.playedIds, [4, 3, 4]);
  });

  testWidgets(
    'parcial gravacao N nao dispara reproducao',
    (tester) async {
      final controller = _RecordingsHelpTestController(
        recordings: [
          _recording(id: 4, name: 'Gravação 3'),
          _recording(id: 3, name: 'Gravação 2'),
          _recording(id: 2, name: 'Gravação 1'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      // These are partial STT transcripts before "detalhes da gravação N" or
      // "renomear gravação N" arrive as the final result. Must NOT trigger
      // playback — they should wait for the complete command.
      await state.debugHandleRecordingReferenceForTesting('gravação 1');
      await tester.pump();
      await state.debugHandleRecordingReferenceForTesting('gravação 2');
      await tester.pump();
      await state.debugHandleRecordingReferenceForTesting('gravação 3');
      await tester.pump();

      expect(
        controller.playedIds,
        isEmpty,
        reason: 'Parcial "gravacao N" não pode disparar reprodução',
      );
    },
  );

  testWidgets('referencias locais de lista nao usam IA contextual', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuarioSemId,
          recordingsController: _RecordingsHelpTestController(
            recordings: [_recording(id: 1, name: 'Gravação 1')],
          ),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

    expect(state.shouldUseAiForVoiceInput('item 1'), isFalse);
    expect(state.shouldUseAiForVoiceInput('gravacao 1'), isFalse);
    expect(state.shouldUseAiForVoiceInput('primeira gravacao'), isFalse);
    expect(state.shouldUseAiForVoiceInput('abrir afinador'), isTrue);
  });

  testWidgets('play manual pausa escuta e stop manual solicita retomada', (
    tester,
  ) async {
    final controller = _RecordingsHelpTestController(
      recordings: [_recording(id: 1, name: 'Ideia')],
    );
    var suspended = 0;
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuarioSemId,
          recordingsController: controller,
          enableVoiceListening: false,
          onVoicePlaybackSuspendedForTesting: () => suspended++,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_circle));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop_circle));
    await tester.pump();

    expect(suspended, 1);
    expect(resumed, 1);
    expect(controller.playedIds, [1]);
    expect(controller.stopCalls, 1);
  });

  testWidgets('completed do player solicita retomada da escuta', (
    tester,
  ) async {
    final controller = _RecordingsHelpTestController(
      recordings: [_recording(id: 1, name: 'Ideia')],
    );
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuarioSemId,
          recordingsController: controller,
          enableVoiceListening: false,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_circle));
    await tester.pump();
    controller.emitPlayerState(PlayerState(false, ProcessingState.completed));
    await tester.pump();

    expect(resumed, 1);
  });

  testWidgets('erro do player na lista solicita retomada da escuta', (
    tester,
  ) async {
    final controller = _RecordingsHelpTestController(
      recordings: [_recording(id: 1, name: 'Ideia')],
    )..throwOnToggle = true;
    var resumed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuarioSemId,
          recordingsController: controller,
          enableVoiceListening: false,
          onVoicePlaybackResumeRequestedForTesting: () => resumed++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_circle));
    await tester.pump();

    expect(resumed, 1);
    expect(controller.playedIds, isEmpty);
  });

  testWidgets(
    'parcial renomear gravacao nao dispara reproducao',
    (tester) async {
      final controller = _RecordingsHelpTestController(
        recordings: [
          _recording(id: 4, name: 'Gravação 3'),
          _recording(id: 3, name: 'Gravação 2'),
          _recording(id: 2, name: 'Gravação 1'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      // Resultado parcial do STT — "renomear gravação 1" sem o "para X"
      // NÃO deve disparar reprodução.
      await state.debugHandleRecordingReferenceForTesting('renomear gravação 1');
      await tester.pump();
      await state.debugHandleRecordingReferenceForTesting('mudar nome da gravação 2');
      await tester.pump();

      expect(controller.playedIds, isEmpty,
          reason: 'Parcial de renomear não pode disparar reprodução');
    },
  );

  testWidgets(
    'renomear gravacao 1 por voz abre modal com nome pre-preenchido',
    (tester) async {
      final recordings = [
        _recording(id: 4, name: 'Gravação 3'),
        _recording(id: 3, name: 'Gravação 2'),
        _recording(id: 2, name: 'Gravação 1'),
      ];
      final controller = _RecordingsHelpTestController(recordings: recordings);

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      // "1" → primeiro item visível (id=4, "Gravação 3") → abre modal
      final renameFuture = state.debugHandleRenameForTesting('1', 'abacate');
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget,
          reason: 'Modal de renomeação deve abrir');
      expect(find.text('abacate'), findsOneWidget,
          reason: 'Campo deve estar pré-preenchido com o novo nome');

      // Confirma tocando "Salvar"
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      await renameFuture;

      expect(controller.renamedPairs, hasLength(1));
      expect(controller.renamedPairs.first.$1, 4,
          reason: 'Deve renomear o primeiro item visível (id=4)');
      expect(controller.renamedPairs.first.$2, 'abacate');
    },
  );

  testWidgets(
    'renomear gravacao por nome textual resolve pelo nome e salva ao confirmar por voz',
    (tester) async {
      final recordings = [
        _recording(id: 4, name: 'Gravação 3'),
        _recording(id: 3, name: 'Refrão'),
        _recording(id: 2, name: 'Gravação 1'),
      ];
      final controller = _RecordingsHelpTestController(recordings: recordings);

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      // "refrao" → encontra por nome normalizado (id=3)
      final renameFuture = state.debugHandleRenameForTesting('refrao', 'beats');
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget);
      expect(state.voiceConfirmationController.hasPendingConfirmation, isTrue,
          reason: 'VoiceConfirmationController deve bloquear outros comandos enquanto modal estiver aberto');

      // Confirma via voz — simula VoiceConfirmationController recebendo "confirmar"
      await (state.voiceConfirmationController as VoiceConfirmationController)
          .handle(const CommandResult(
        originalText: 'confirmar',
        normalizedText: 'confirmar',
        type: VoiceCommandType.confirmarAcao,
        recognized: true,
        tipoComando: 'confirmarAcao',
      ));
      await tester.pumpAndSettle();
      await renameFuture;

      expect(controller.renamedPairs, hasLength(1));
      expect(controller.renamedPairs.first.$1, 3,
          reason: 'Deve renomear por correspondência de nome (id=3)');
      expect(controller.renamedPairs.first.$2, 'beats');
    },
  );

  testWidgets(
    'voz cancelar durante modal de renomear nao salva',
    (tester) async {
      final controller = _RecordingsHelpTestController(
        recordings: [_recording(id: 1, name: 'Ideia')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      final renameFuture = state.debugHandleRenameForTesting('1', 'novo nome');
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget);

      // Cancela via voz
      await (state.voiceConfirmationController as VoiceConfirmationController)
          .handle(const CommandResult(
        originalText: 'cancelar',
        normalizedText: 'cancelar',
        type: VoiceCommandType.cancelarAcao,
        recognized: true,
        tipoComando: 'cancelarAcao',
      ));
      await tester.pumpAndSettle();
      await renameFuture;

      expect(controller.renamedPairs, isEmpty,
          reason: 'Cancelar por voz não deve salvar a renomeação');
    },
  );

  testWidgets(
    'modal renomear bloqueia reproducao por voz via voiceConfirmationController',
    (tester) async {
      final controller = _RecordingsHelpTestController(
        recordings: [_recording(id: 1, name: 'Ideia')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      final renameFuture = state.debugHandleRenameForTesting('1', 'beats');
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget);

      // Enquanto modal está aberto, "reproduzir gravação 1" deve ser bloqueado
      final result = await (state.voiceConfirmationController
              as VoiceConfirmationController)
          .handle(const CommandResult(
        originalText: 'reproduzir gravacao 1',
        normalizedText: 'reproduzir gravacao 1',
        type: VoiceCommandType.reproduzirGravacao,
        recognized: true,
        tipoComando: 'reproduzirGravacao',
        parametro: '1',
      ));

      expect(result.action, VoiceConfirmationAction.blocked,
          reason: 'Reprodução deve ser bloqueada durante modal de renomeação');
      expect(controller.playedIds, isEmpty);

      // Cleanup
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await renameFuture;
    },
  );

  testWidgets(
    'renomear referencia inexistente nao abre modal nem causa crash',
    (tester) async {
      final controller = _RecordingsHelpTestController(
        recordings: [_recording(id: 1, name: 'Ideia')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MinhasGravacoesPage(
            usuario: _usuarioSemId,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(MinhasGravacoesPage)) as dynamic;

      // Índice 99 está fora do range — não deve abrir modal, nem renomear.
      await state.debugHandleRenameForTesting('99', 'abacate');
      await tester.pump();

      expect(find.text('Renomear gravação'), findsNothing,
          reason: 'Modal não deve abrir para referência inválida');
      expect(controller.renamedPairs, isEmpty);
      expect(controller.playedIds, isEmpty);
    },
  );
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

final _usuarioSemId = Usuario(
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

class _RecordingsHelpTestController extends RecordingsListController {
  _RecordingsHelpTestController({List<Gravacao> recordings = const []})
    : _testState = RecordingsListState(
        loading: false,
        error: null,
        recordings: recordings,
        playingRecordingId: null,
        pendingDeletion: null,
        searchTerm: '',
      );

  RecordingsListState _testState;
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final playedIds = <int?>[];
  var stopCalls = 0;
  var throwOnToggle = false;

  @override
  RecordingsListState get state => _testState;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Future<void> load({required int? usuarioId, String? searchTerm}) async {}

  @override
  RecordingPlaybackResolution resolvePlaybackCommand(String? reference) {
    final normalized = (reference ?? '').trim();
    if (normalized.isEmpty) {
      return RecordingPlaybackResolution.message(
        'Diga qual gravação deseja tocar.',
      );
    }

    final titleReference = normalized
        .replaceFirst(
          RegExp(r'^(tocar|toque|reproduzir|reproduza|play) '),
          '',
        )
        .replaceFirst(RegExp(r'^a '), '')
        .trim();
    for (final recording in _testState.recordings) {
      if (_normalize(recording.nome) == _normalize(titleReference)) {
        return RecordingPlaybackResolution.play(recording);
      }
    }

    final index = switch (normalized) {
      String text
          when text.contains('item 1') ||
              text.contains('item um') ||
              text.contains('primeira') =>
        0,
      String text
          when text.contains('item 2') ||
              text.contains('item dois') ||
              text.contains('segunda') =>
        1,
      String text when text.contains('item 3') || text.contains('item tres') =>
        2,
      _ => -1,
    };

    if (index < 0 || index >= _testState.recordings.length) {
      return RecordingPlaybackResolution.message(
        'Não encontrei essa gravação na lista.',
      );
    }
    return RecordingPlaybackResolution.play(_testState.recordings[index]);
  }

  String _normalize(String text) {
    return const <String, String>{
      'ç': 'c',
      'ã': 'a',
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
    }.entries.fold(
      text.toLowerCase(),
      (current, entry) => current.replaceAll(entry.key, entry.value),
    );
  }

  final renamedPairs = <(int?, String)>[];

  @override
  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String newName,
    required int? usuarioId,
    bool byVoice = false,
  }) async {
    renamedPairs.add((gravacao.id, newName));
    final updated = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      projetoId: gravacao.projetoId,
      nome: newName,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
      tamanhoBytes: gravacao.tamanhoBytes,
      formatoAudio: gravacao.formatoAudio,
    );
    final recordings = List.of(_testState.recordings);
    final idx = recordings.indexWhere((r) => r.id == gravacao.id);
    if (idx != -1) recordings[idx] = updated;
    _testState = _testState.copyWith(recordings: recordings);
    notifyListeners();
    return updated;
  }

  @override
  Future<void> togglePlayback(
    Gravacao gravacao, {
    required int? usuarioId,
  }) async {
    if (throwOnToggle) {
      throw StateError('player failure');
    }

    if (_testState.playingRecordingId == gravacao.id) {
      await stopPlayback();
      return;
    }
    playedIds.add(gravacao.id);
    _testState = _testState.copyWith(playingRecordingId: gravacao.id);
    notifyListeners();
  }

  @override
  Future<void> stopPlayback() async {
    stopCalls += 1;
    _testState = _testState.copyWith(clearPlayingRecording: true);
    notifyListeners();
  }

  void emitPlayerState(PlayerState state) {
    _playerStateController.add(state);
  }

  @override
  void dispose() {
    _playerStateController.close();
    super.dispose();
  }
}

Gravacao _recording({required int id, required String name}) {
  return Gravacao(
    id: id,
    usuarioId: _usuario.id!,
    nome: name,
    caminhoArquivo: '/tmp/$id.m4a',
    dataCriacao: '2026-06-15T10:00:00.000',
    tamanhoBytes: 128,
  );
}
