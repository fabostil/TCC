import 'package:app_voz/features/projects/controllers/projects_list_controller.dart';
import 'package:app_voz/features/projects/pages/meus_projetos_page.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/projeto.dart';
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

  testWidgets(
    'descricao e descricao do projeto atuam no formulario de projeto',
    (tester) async {
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

      var result = await _dispatchProjectsCommand(tester, 'descricao');
      await tester.pump();

      expect(result.handled, isTrue);
      expect(
        find.widgetWithText(TextFormField, 'Descrição (opcional)'),
        findsOneWidget,
      );

      result = await _dispatchProjectsCommand(
        tester,
        'descricao do projeto ideia para tocar ao vivo',
      );
      await tester.pump();

      expect(result.handled, isTrue);
      expect(find.text('Ideia para tocar ao vivo.'), findsOneWidget);
    },
  );

  testWidgets(
    'comando reproduzir gravacao em projetos da orientacao sem abrir ajuda',
    (tester) async {
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

      final result = await _dispatchProjectsCommand(
        tester,
        'reproduzir gravacao',
      );
      await tester.pump();

      expect(result.handled, isTrue);
      expect(result.statusMessage, contains('Minhas Gravações'));
      expect(find.text('Comandos em projetos'), findsNothing);
    },
  );

  testWidgets(
    'comando iniciar gravacao em projetos da orientacao sem abrir ajuda',
    (tester) async {
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

      final result = await _dispatchProjectsCommand(tester, 'gravar');
      await tester.pump();

      expect(result.handled, isTrue);
      expect(result.statusMessage, contains('Minhas Gravações'));
      expect(find.text('Comandos em projetos'), findsNothing);
    },
  );

  testWidgets('comando ajuda em projetos abre dialogo de ajuda', (
    tester,
  ) async {
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

    final result = await _dispatchProjectsCommand(tester, 'ajuda');
    await tester.pumpAndSettle();

    expect(result.handled, isTrue);
    expect(find.text('Comandos em projetos'), findsOneWidget);
  });

  testWidgets('excluir projeto continua abrindo confirmacao', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MeusProjetosPage(
          usuario: _usuario,
          projectsController: _ProjectsHelpTestController(
            projects: [_project(id: 1, name: 'Demo')],
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

    expect(find.text('Excluir projeto?'), findsOneWidget);
    expect(find.text('Excluir'), findsWidgets);
  });
}

Future<VoiceCommandPageResult> _dispatchProjectsCommand(
  WidgetTester tester,
  String text,
) async {
  final state = tester.state(find.byType(MeusProjetosPage)) as dynamic;
  final result = const CommandService().interpret(text);
  return await state.voiceCommandDispatcher.dispatch(result)
      as VoiceCommandPageResult;
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

class _ProjectsHelpTestController extends ProjectsListController {
  _ProjectsHelpTestController({List<Projeto> projects = const []})
    : _testState = ProjectsListState(
        loading: false,
        saving: false,
        error: null,
        projects: projects,
        creationActive: false,
        searchTerm: '',
      );

  ProjectsListState _testState;

  @override
  ProjectsListState get state => _testState;

  @override
  Future<void> load({required int? usuarioId, String? searchTerm}) async {}

  @override
  void showCreation({bool clear = false}) {
    _testState = _testState.copyWith(creationActive: true);
    notifyListeners();
  }
}

Projeto _project({required int id, required String name}) {
  return Projeto(
    id: id,
    usuarioId: _usuario.id!,
    nome: name,
    descricao: 'Ideia inicial',
    dataCriacao: '2026-06-15T10:00:00.000',
  );
}
