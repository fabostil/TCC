import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/historico_acao.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/repositories/gravacao_repository.dart';
import 'package:app_voz/repositories/historico_repository.dart';
import 'package:app_voz/repositories/projeto_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_utils.dart';

void main() {
  const databaseName = 'historico_repository_test.db';
  late UsuarioRepository usuarioRepository;
  late ProjetoRepository projetoRepository;
  late GravacaoRepository gravacaoRepository;
  late HistoricoRepository repository;
  late int usuarioId;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    usuarioRepository = UsuarioRepository.instance;
    projetoRepository = ProjetoRepository.instance;
    gravacaoRepository = GravacaoRepository.instance;
    repository = HistoricoRepository.instance;
    await useRepositoryTestDatabase(databaseName);
    await resetRepositoryTestDatabase(databaseName);

    usuarioId = await _criarUsuario(
      usuarioRepository,
      email: 'alex@example.com',
    );
  });

  tearDown(() async {
    await resetRepositoryTestDatabase(databaseName);
  });

  group('HistoricoRepository', () {
    test('banco vazio retorna listas vazias e contadores zerados', () async {
      expect(await repository.listarPorUsuario(usuarioId), isEmpty);
      expect(await repository.listarPorProjeto(999), isEmpty);
      expect(await repository.listarPorGravacao(999), isEmpty);
      expect(
        await repository.contarPorTipo(usuarioId: usuarioId, tipo: 'gravacao'),
        0,
      );
      expect(await repository.contarAcoesPorTipo(usuarioId), isEmpty);
    });

    test('registrar trimma campos e persiste acao sem relacao', () async {
      final dataHora = DateTime.parse('2026-06-10T10:00:00.000');

      final id = await repository.registrar(
        usuarioId: usuarioId,
        tipo: ' gravacao_iniciada ',
        descricao: ' Iniciou gravacao ',
        dataHora: dataHora,
      );

      final historico = await repository.listarPorUsuario(usuarioId);

      expect(historico, hasLength(1));
      expect(historico.single.id, id);
      expect(historico.single.usuarioId, usuarioId);
      expect(historico.single.tipo, 'gravacao_iniciada');
      expect(historico.single.descricao, 'Iniciou gravacao');
      expect(historico.single.dataHora, dataHora.toIso8601String());
      expect(historico.single.projetoId, isNull);
      expect(historico.single.gravacaoId, isNull);
    });

    test(
      'registrarAcao persiste relacoes e filtros por projeto e gravacao',
      () async {
        final projetoId = await _criarProjeto(projetoRepository, usuarioId);
        final gravacaoId = await _criarGravacao(
          gravacaoRepository,
          usuarioId: usuarioId,
          projetoId: projetoId,
        );
        final outroProjetoId = await _criarProjeto(
          projetoRepository,
          usuarioId,
          nome: 'Outro projeto',
        );

        final id = await repository.registrarAcao(
          HistoricoAcao(
            usuarioId: usuarioId,
            projetoId: projetoId,
            gravacaoId: gravacaoId,
            tipo: 'gravacao_finalizada',
            descricao: 'Finalizou take',
            dataHora: '2026-06-10T10:00:00.000',
          ),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          projetoId: outroProjetoId,
          tipo: 'projeto_aberto',
          descricao: 'Abriu outro projeto',
          dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
        );

        final porProjeto = await repository.listarPorProjeto(projetoId);
        final porGravacao = await repository.listarPorGravacao(gravacaoId);

        expect(porProjeto.map((historico) => historico.id), [id]);
        expect(porGravacao.map((historico) => historico.id), [id]);
        expect(porProjeto.single.projetoId, projetoId);
        expect(porProjeto.single.gravacaoId, gravacaoId);
      },
    );

    test('lista por usuario em ordem recente e respeita limite', () async {
      final antigoId = await repository.registrar(
        usuarioId: usuarioId,
        tipo: 'app_aberto',
        descricao: 'Abriu app',
        dataHora: DateTime.parse('2026-06-10T09:00:00.000'),
      );
      final recenteId = await repository.registrar(
        usuarioId: usuarioId,
        tipo: 'dashboard_aberto',
        descricao: 'Abriu dashboard',
        dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
      );

      final todos = await repository.listarPorUsuario(usuarioId);
      final limitado = await repository.listarPorUsuario(usuarioId, limite: 1);

      expect(todos.map((historico) => historico.id), [recenteId, antigoId]);
      expect(limitado.map((historico) => historico.id), [recenteId]);
    });

    test(
      'conta por tipo e agrega metricas ordenando por total e tipo',
      () async {
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'reproducao',
          descricao: 'Tocou gravacao',
          dataHora: DateTime.parse('2026-06-10T09:00:00.000'),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'reproducao',
          descricao: 'Tocou outra gravacao',
          dataHora: DateTime.parse('2026-06-10T10:00:00.000'),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'abrir_dashboard',
          descricao: 'Abriu dashboard',
          dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'abrir_editor',
          descricao: 'Abriu editor',
          dataHora: DateTime.parse('2026-06-10T12:00:00.000'),
        );

        final totalReproducao = await repository.contarPorTipo(
          usuarioId: usuarioId,
          tipo: 'reproducao',
        );
        final metricas = await repository.contarAcoesPorTipo(usuarioId);

        expect(totalReproducao, 2);
        expect(metricas.map((metrica) => metrica.tipo), [
          'reproducao',
          'abrir_dashboard',
          'abrir_editor',
        ]);
        expect(metricas.map((metrica) => metrica.total), [2, 1, 1]);
      },
    );

    test('filtros e agregacoes ficam isolados por usuario', () async {
      final outroUsuarioId = await _criarUsuario(
        usuarioRepository,
        email: 'bia@example.com',
      );

      await repository.registrar(
        usuarioId: usuarioId,
        tipo: 'gravacao',
        descricao: 'Usuario principal',
        dataHora: DateTime.parse('2026-06-10T10:00:00.000'),
      );
      await repository.registrar(
        usuarioId: outroUsuarioId,
        tipo: 'gravacao',
        descricao: 'Outro usuario',
        dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
      );

      final historico = await repository.listarPorUsuario(usuarioId);
      final metricas = await repository.contarAcoesPorTipo(usuarioId);

      expect(historico, hasLength(1));
      expect(historico.single.usuarioId, usuarioId);
      expect(
        await repository.contarPorTipo(usuarioId: usuarioId, tipo: 'gravacao'),
        1,
      );
      expect(metricas.single.tipo, 'gravacao');
      expect(metricas.single.total, 1);
    });

    test(
      'contador por tipo usa parametro seguro para texto malicioso',
      () async {
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'gravacao',
          descricao: 'Registrou gravacao',
          dataHora: DateTime.parse('2026-06-10T10:00:00.000'),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          tipo: 'reproducao',
          descricao: 'Tocou gravacao',
          dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
        );

        final totalMalicioso = await repository.contarPorTipo(
          usuarioId: usuarioId,
          tipo: "' OR 1=1 --",
        );

        expect(totalMalicioso, 0);
        expect(await repository.listarPorUsuario(usuarioId), hasLength(2));
      },
    );
  });
}

Future<int> _criarUsuario(
  UsuarioRepository repository, {
  required String email,
}) async {
  await repository.cadastrarUsuario(
    nome: 'Usuario Teste',
    email: email,
    senha: 'abc12345',
  );
  return (await repository.buscarPorEmail(email))!.id!;
}

Future<int> _criarProjeto(
  ProjetoRepository repository,
  int usuarioId, {
  String nome = 'Projeto teste',
}) {
  return repository.criarProjeto(
    Projeto(
      usuarioId: usuarioId,
      nome: nome,
      dataCriacao: '2026-06-10T09:00:00.000',
    ),
  );
}

Future<int> _criarGravacao(
  GravacaoRepository repository, {
  required int usuarioId,
  required int projetoId,
}) {
  return repository.criarGravacao(
    Gravacao(
      usuarioId: usuarioId,
      projetoId: projetoId,
      nome: 'Take 1',
      caminhoArquivo: '/tmp/take1.m4a',
      dataCriacao: '2026-06-10T09:30:00.000',
    ),
  );
}
