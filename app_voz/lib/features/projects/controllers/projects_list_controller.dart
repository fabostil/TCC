import 'package:flutter/foundation.dart';

import '../../../core/ui/user_facing_messages.dart';
import '../../../models/projeto.dart';
import '../../../repositories/projeto_repository.dart';
import '../../voices/services/command_service.dart';

class ProjectsListState {
  final bool loading;
  final bool saving;
  final String? error;
  final List<Projeto> projects;
  final bool creationActive;
  final String searchTerm;

  const ProjectsListState({
    required this.loading,
    required this.saving,
    required this.error,
    required this.projects,
    required this.creationActive,
    required this.searchTerm,
  });

  const ProjectsListState.initial()
    : loading = true,
      saving = false,
      error = null,
      projects = const [],
      creationActive = false,
      searchTerm = '';

  ProjectsListState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    List<Projeto>? projects,
    bool? creationActive,
    String? searchTerm,
  }) {
    return ProjectsListState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : error ?? this.error,
      projects: projects ?? this.projects,
      creationActive: creationActive ?? this.creationActive,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }
}

class ProjectsListController extends ChangeNotifier {
  ProjectsListController({
    ProjetoRepository? projetoRepository,
    CommandService commandService = const CommandService(),
  }) : _projetoRepository = projetoRepository ?? ProjetoRepository.instance,
       _commandService = commandService;

  final ProjetoRepository _projetoRepository;
  final CommandService _commandService;

  ProjectsListState _state = const ProjectsListState.initial();

  ProjectsListState get state => _state;

  Future<void> load({required int? usuarioId, String? searchTerm}) async {
    final effectiveSearchTerm = searchTerm ?? _state.searchTerm;

    if (usuarioId == null) {
      _setState(
        _state.copyWith(
          loading: false,
          error: 'Usuario sem identificacao para buscar projetos.',
          searchTerm: effectiveSearchTerm,
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        loading: true,
        clearError: true,
        searchTerm: effectiveSearchTerm,
      ),
    );

    try {
      final projects = await _projetoRepository.listarProjetosPorUsuario(
        usuarioId,
        termoBusca: effectiveSearchTerm,
      );
      _setState(_state.copyWith(loading: false, projects: projects));
    } catch (_) {
      _setState(
        _state.copyWith(
          loading: false,
          error: UserFacingMessages.dataLoadError,
        ),
      );
    }
  }

  void showCreation({bool clear = false}) {
    _setState(_state.copyWith(creationActive: true));
  }

  void cancelCreation() {
    _setState(_state.copyWith(creationActive: false, saving: false));
  }

  Future<Projeto> createProject({
    required int? usuarioId,
    required String name,
    String? description,
    DateTime? createdAt,
  }) async {
    final cleanName = name.trim();
    if (usuarioId == null) {
      throw StateError('Usuario sem identificacao para criar projeto.');
    }
    if (cleanName.isEmpty) {
      throw ArgumentError('Nome do projeto nao pode ficar vazio.');
    }

    _setState(_state.copyWith(saving: true));

    final project = Projeto(
      usuarioId: usuarioId,
      nome: _uniqueName(cleanName),
      descricao: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      dataCriacao: (createdAt ?? DateTime.now()).toIso8601String(),
    );

    final id = await _projetoRepository.criarProjeto(project);
    final created = Projeto(
      id: id,
      usuarioId: project.usuarioId,
      nome: project.nome,
      descricao: project.descricao,
      dataCriacao: project.dataCriacao,
    );

    _setState(
      _state.copyWith(
        saving: false,
        creationActive: false,
        projects: [created, ..._state.projects],
      ),
    );
    return created;
  }

  Future<Projeto> renameProject({
    required Projeto project,
    required String newName,
  }) async {
    if (project.id == null) {
      throw ArgumentError('Projeto sem id nao pode ser renomeado.');
    }

    final renamed = Projeto(
      id: project.id,
      usuarioId: project.usuarioId,
      nome: _uniqueName(newName, ignoreId: project.id),
      descricao: project.descricao,
      dataCriacao: project.dataCriacao,
    );

    await _projetoRepository.atualizarProjeto(renamed);

    final projects = [..._state.projects];
    final index = projects.indexWhere((item) => item.id == project.id);
    if (index != -1) {
      projects[index] = renamed;
      _setState(_state.copyWith(projects: projects));
    }

    return renamed;
  }

  Future<void> deleteProject({required Projeto project}) async {
    final projectId = project.id;
    if (projectId == null) {
      throw ArgumentError('Não consegui identificar o projeto para remover.');
    }

    await _projetoRepository.removerProjeto(projectId);

    final projects = _state.projects
        .where((item) => item.id != projectId)
        .toList(growable: false);
    _setState(_state.copyWith(projects: projects));
  }

  Projeto? findByName(String? name) {
    final normalizedName = _commandService.normalize(name ?? '');
    if (normalizedName.isEmpty) {
      return null;
    }

    for (final project in _state.projects) {
      if (_commandService.normalize(project.nome).contains(normalizedName)) {
        return project;
      }
    }

    return null;
  }

  String _uniqueName(String baseName, {int? ignoreId}) {
    final base = baseName.trim();
    if (base.isEmpty) {
      throw ArgumentError('Nome do projeto nao pode ficar vazio.');
    }

    final existingNames = _state.projects
        .where((project) => project.id != ignoreId)
        .map((project) => _commandService.normalize(project.nome))
        .toSet();

    var candidate = base;
    var counter = 1;
    while (existingNames.contains(_commandService.normalize(candidate))) {
      candidate = '$base$counter';
      counter++;
    }

    return candidate;
  }

  void _setState(ProjectsListState nextState) {
    _state = nextState;
    notifyListeners();
  }
}
