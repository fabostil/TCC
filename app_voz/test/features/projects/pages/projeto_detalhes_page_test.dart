import 'package:app_voz/features/projects/pages/projeto_detalhes_page.dart';
import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abrir editor por voz usa o projeto atual', (tester) async {
    final projeto = Projeto(
      id: 42,
      usuarioId: 7,
      nome: 'Demo TCC',
      descricao: 'Projeto da apresentacao',
      dataCriacao: '2026-06-17T10:00:00.000',
    );
    Projeto? projetoAberto;

    await tester.pumpWidget(
      MaterialApp(
        home: ProjetoDetalhesPage(
          usuario: _usuario,
          projeto: projeto,
          recordingsController: _FakeRecordingsListController(),
          enableVoiceListening: false,
          onOpenEditorForTesting: (currentProject) {
            projetoAberto = currentProject;
          },
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;
    final result =
        await state.debugHandleVoiceCommandForTesting('abrir editor')
            as VoiceCommandPageResult;
    await tester.pump();

    expect(result.handled, isTrue);
    expect(result.restartListening, isFalse);
    expect(projetoAberto, same(projeto));
  });
}

final _usuario = Usuario(
  id: 7,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

class _FakeRecordingsListController extends RecordingsListController {
  final _state = const RecordingsListState(
    loading: false,
    error: null,
    recordings: [],
    playingRecordingId: null,
    pendingDeletion: null,
    searchTerm: '',
  );

  @override
  RecordingsListState get state => _state;

  @override
  Future<void> loadByProject({required int? projetoId, String? searchTerm}) {
    return Future<void>.value();
  }
}
