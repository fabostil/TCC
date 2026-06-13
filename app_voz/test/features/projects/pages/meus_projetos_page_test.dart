import 'package:app_voz/features/projects/controllers/projects_list_controller.dart';
import 'package:app_voz/features/projects/pages/meus_projetos_page.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abre e fecha ajuda contextual de projetos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MeusProjetosPage(
          usuario: _usuario,
          projectsController: _ProjectsHelpTestController(),
          enableVoiceListening: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('projects_voice_command_help_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('projects_voice_command_help_button')),
    );
    await tester.pump();

    expect(find.text('Comandos em projetos'), findsOneWidget);
    expect(find.text('Novo projeto'), findsWidgets);
    expect(find.text('Descer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('voice_command_help_close_button')));
    await tester.pump();

    expect(find.text('Comandos em projetos'), findsNothing);
  });
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

class _ProjectsHelpTestController extends ProjectsListController {
  final ProjectsListState _testState = const ProjectsListState(
    loading: false,
    saving: false,
    error: null,
    projects: [],
    creationActive: false,
    searchTerm: '',
  );

  @override
  ProjectsListState get state => _testState;

  @override
  Future<void> load({required int? usuarioId, String? searchTerm}) async {}
}
