import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/recordings/pages/minhas_gravacoes_page.dart';
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
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

class _RecordingsHelpTestController extends RecordingsListController {
  final RecordingsListState _testState = const RecordingsListState(
    loading: false,
    error: null,
    recordings: [],
    playingRecordingId: null,
    pendingDeletion: null,
    searchTerm: '',
  );

  @override
  RecordingsListState get state => _testState;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Future<void> load({required int? usuarioId, String? searchTerm}) async {}
}
