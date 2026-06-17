import 'dart:async';

import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/recordings/pages/minhas_gravacoes_page.dart';
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
    await state.debugHandleRecordingReferenceForTesting('gravação 1');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('item 1');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('item 2');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('primeira gravação');
    await tester.pump();

    expect(controller.playedIds, [2, 4, 3, 4]);
  });

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
