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
}

final _usuario = Usuario(
  id: 1,
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

  final RecordingsListState _testState;

  @override
  RecordingsListState get state => _testState;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Future<void> load({required int? usuarioId, String? searchTerm}) async {}
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
