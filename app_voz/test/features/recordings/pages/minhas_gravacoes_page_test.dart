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
    expect(find.text('Tocar'), findsOneWidget);
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

  testWidgets('cards mostram numeracao visual sem usar id do banco', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinhasGravacoesPage(
          usuario: _usuario,
          recordingsController: _RecordingsHelpTestController(
            recordings: [
              _recording(id: 4, name: 'Mais recente'),
              _recording(id: 3, name: 'Segundo card'),
              _recording(id: 2, name: 'Terceiro card'),
            ],
          ),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Gravação 1'), findsOneWidget);
    expect(find.text('Gravação 2'), findsOneWidget);
    expect(find.text('Gravação 3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Gravação 1')).dy,
      lessThan(tester.getTopLeft(find.text('Gravação 2')).dy),
    );
  });

  testWidgets('referencia parcial por voz toca indice visual atual', (
    tester,
  ) async {
    final controller = _RecordingsHelpTestController(
      recordings: [
        _recording(id: 4, name: 'Mais recente'),
        _recording(id: 3, name: 'Segundo card'),
        _recording(id: 2, name: 'Terceiro card'),
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
    await state.debugHandleRecordingReferenceForTesting('gravação dois');
    await tester.pump();
    await state.debugHandleRecordingReferenceForTesting('primeira gravação');
    await tester.pump();

    expect(controller.playedIds, [4, 3, 4]);
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

    final index = switch (normalized) {
      String text
          when text.contains('1') ||
              text.contains('um') ||
              text.contains('primeira') =>
        0,
      String text
          when text.contains('2') ||
              text.contains('dois') ||
              text.contains('segunda') =>
        1,
      String text when text.contains('3') || text.contains('tres') => 2,
      _ => -1,
    };

    if (index < 0 || index >= _testState.recordings.length) {
      return RecordingPlaybackResolution.message(
        'Não encontrei essa gravação na lista.',
      );
    }
    return RecordingPlaybackResolution.play(_testState.recordings[index]);
  }

  @override
  Future<void> togglePlayback(
    Gravacao gravacao, {
    required int? usuarioId,
  }) async {
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
