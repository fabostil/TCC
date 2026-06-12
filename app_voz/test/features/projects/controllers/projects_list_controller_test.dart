import 'package:app_voz/features/projects/controllers/projects_list_controller.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/repositories/projeto_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectsListController', () {
    late FakeProjetoRepository repository;
    late ProjectsListController controller;

    setUp(() {
      repository = FakeProjetoRepository();
      controller = ProjectsListController(projetoRepository: repository);
    });

    tearDown(() {
      controller.dispose();
    });

    test('carrega projetos por usuario e termo', () async {
      repository.projects = [
        _project(id: 1, name: 'Demo'),
        _project(id: 2, name: 'Beat'),
      ];

      await controller.load(usuarioId: 7, searchTerm: 'demo');

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isNull);
      expect(controller.state.projects.map((project) => project.nome), [
        'Demo',
        'Beat',
      ]);
      expect(repository.lastUserId, 7);
      expect(repository.lastSearchTerm, 'demo');
    });

    test('cria projeto com nome unico e atualiza estado', () async {
      repository.projects = [_project(id: 1, name: 'Demo')];
      await controller.load(usuarioId: 7);

      final created = await controller.createProject(
        usuarioId: 7,
        name: 'Demo',
        createdAt: DateTime(2026, 5, 19),
      );

      expect(created.nome, 'Demo1');
      expect(controller.state.saving, isFalse);
      expect(controller.state.creationActive, isFalse);
      expect(controller.state.projects.first.nome, 'Demo1');
    });

    test('renomeia projeto mantendo nomes unicos', () async {
      final first = _project(id: 1, name: 'Demo');
      final second = _project(id: 2, name: 'Beat');
      repository.projects = [first, second];
      await controller.load(usuarioId: 7);

      final renamed = await controller.renameProject(
        project: second,
        newName: 'Demo',
      );

      expect(renamed.nome, 'Demo1');
      expect(controller.state.projects.last.nome, 'Demo1');
      expect(repository.updatedProjects.single.nome, 'Demo1');
    });

    test('exclui projeto e remove do estado', () async {
      final first = _project(id: 1, name: 'Demo');
      final second = _project(id: 2, name: 'Beat');
      repository.projects = [first, second];
      await controller.load(usuarioId: 7);

      await controller.deleteProject(project: first);

      expect(repository.removedProjectIds, [1]);
      expect(controller.state.projects.map((project) => project.nome), [
        'Beat',
      ]);
    });

    test('busca projeto por nome normalizado', () async {
      repository.projects = [_project(id: 1, name: 'Ideia acústica')];
      await controller.load(usuarioId: 7);

      final found = controller.findByName('acustica');

      expect(found, isNotNull);
      expect(found!.id, 1);
    });
  });
}

Projeto _project({required int id, required String name}) {
  return Projeto(
    id: id,
    usuarioId: 7,
    nome: name,
    dataCriacao: '2026-05-19T10:00:00.000',
  );
}

class FakeProjetoRepository implements ProjetoRepository {
  List<Projeto> projects = [];
  final updatedProjects = <Projeto>[];
  final removedProjectIds = <int>[];
  int? lastUserId;
  String? lastSearchTerm;
  int nextId = 10;

  @override
  Future<int> criarProjeto(Projeto projeto) async {
    final id = nextId++;
    projects = [
      Projeto(
        id: id,
        usuarioId: projeto.usuarioId,
        nome: projeto.nome,
        descricao: projeto.descricao,
        dataCriacao: projeto.dataCriacao,
      ),
      ...projects,
    ];
    return id;
  }

  @override
  Future<List<Projeto>> listarProjetosPorUsuario(
    int usuarioId, {
    String? termoBusca,
  }) async {
    lastUserId = usuarioId;
    lastSearchTerm = termoBusca;
    return projects;
  }

  @override
  Future<int> atualizarProjeto(Projeto projeto) async {
    updatedProjects.add(projeto);
    return 1;
  }

  @override
  Future<Projeto?> buscarProjetoPorId(int id) async {
    return projects.where((project) => project.id == id).firstOrNull;
  }

  @override
  Future<int> removerProjeto(int id) async {
    removedProjectIds.add(id);
    projects = projects.where((project) => project.id != id).toList();
    return 1;
  }
}
