import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/repositories/gravacao_repository.dart';
import 'package:app_voz/repositories/projeto_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_utils.dart';

void main() {
  const databaseName = 'project_recording_repository_test.db';
  late UsuarioRepository usuarioRepository;
  late ProjetoRepository projetoRepository;
  late GravacaoRepository gravacaoRepository;
  late int usuarioId;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    usuarioRepository = UsuarioRepository.instance;
    projetoRepository = ProjetoRepository.instance;
    gravacaoRepository = GravacaoRepository.instance;
    await useRepositoryTestDatabase(databaseName);
    await resetRepositoryTestDatabase(databaseName);

    await usuarioRepository.cadastrarUsuario(
      nome: 'Alex',
      email: 'alex@example.com',
      senha: 'abc12345',
    );
    usuarioId = (await usuarioRepository.buscarPorEmail(
      'alex@example.com',
    ))!.id!;
  });

  tearDown(() async {
    await resetRepositoryTestDatabase(databaseName);
  });

  group('ProjetoRepository', () {
    test('cria, lista, busca, atualiza e remove projeto por usuario', () async {
      final id = await projetoRepository.criarProjeto(
        Projeto(
          usuarioId: usuarioId,
          nome: 'Demo',
          descricao: 'Ideia inicial',
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );

      final listado = await projetoRepository.listarProjetosPorUsuario(
        usuarioId,
      );
      final encontrado = await projetoRepository.buscarProjetoPorId(id);

      expect(listado, hasLength(1));
      expect(encontrado, isNotNull);
      expect(encontrado!.nome, 'Demo');

      final alterados = await projetoRepository.atualizarProjeto(
        Projeto(
          id: id,
          usuarioId: usuarioId,
          nome: 'Demo renomeada',
          descricao: 'Descricao atualizada',
          dataCriacao: encontrado.dataCriacao,
        ),
      );

      expect(alterados, 1);
      expect(
        (await projetoRepository.buscarProjetoPorId(id))!.nome,
        'Demo renomeada',
      );

      expect(await projetoRepository.removerProjeto(id), 1);
      expect(await projetoRepository.buscarProjetoPorId(id), isNull);
    });

    test('atualizar projeto sem id falha explicitamente', () async {
      expect(
        () => projetoRepository.atualizarProjeto(
          Projeto(
            usuarioId: usuarioId,
            nome: 'Sem id',
            dataCriacao: '2026-05-19T10:00:00.000',
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'busca projetos por nome e descricao usando termo parametrizado',
      () async {
        await projetoRepository.criarProjeto(
          Projeto(
            usuarioId: usuarioId,
            nome: 'Demo acustica',
            descricao: 'Ideia com violao',
            dataCriacao: '2026-05-19T10:00:00.000',
          ),
        );
        await projetoRepository.criarProjeto(
          Projeto(
            usuarioId: usuarioId,
            nome: 'Beat urbano',
            descricao: 'Bateria pesada',
            dataCriacao: '2026-05-19T11:00:00.000',
          ),
        );

        final porNome = await projetoRepository.listarProjetosPorUsuario(
          usuarioId,
          termoBusca: 'demo',
        );
        final porDescricao = await projetoRepository.listarProjetosPorUsuario(
          usuarioId,
          termoBusca: 'violao',
        );

        expect(porNome.map((projeto) => projeto.nome), ['Demo acustica']);
        expect(porDescricao.map((projeto) => projeto.nome), ['Demo acustica']);
      },
    );
  });

  group('GravacaoRepository', () {
    test(
      'lista gravacoes por usuario e por projeto em ordem recente',
      () async {
        final projetoId = await projetoRepository.criarProjeto(
          Projeto(
            usuarioId: usuarioId,
            nome: 'Projeto',
            dataCriacao: '2026-05-19T10:00:00.000',
          ),
        );

        final antigaId = await gravacaoRepository.criarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            projetoId: projetoId,
            nome: 'Antiga',
            caminhoArquivo: '/tmp/antiga.m4a',
            dataCriacao: '2026-05-19T09:00:00.000',
            duracaoSegundos: 12,
          ),
        );
        final recenteId = await gravacaoRepository.criarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            projetoId: projetoId,
            nome: 'Recente',
            caminhoArquivo: '/tmp/recente.m4a',
            dataCriacao: '2026-05-19T11:00:00.000',
            duracaoSegundos: 30,
            tamanhoBytes: 2048,
            formatoAudio: 'm4a',
          ),
        );

        final porUsuario = await gravacaoRepository.listarGravacoesPorUsuario(
          usuarioId,
        );
        final porProjeto = await gravacaoRepository.listarGravacoesPorProjeto(
          projetoId,
        );

        expect(porUsuario.map((gravacao) => gravacao.id), [
          recenteId,
          antigaId,
        ]);
        expect(porProjeto.map((gravacao) => gravacao.nome), [
          'Recente',
          'Antiga',
        ]);
        expect(porProjeto.first.duracaoSegundos, 30);
        expect(porProjeto.first.status, 'concluida');
        expect(porProjeto.first.tamanhoBytes, 2048);
        expect(porProjeto.first.formatoAudio, 'm4a');
      },
    );

    test('atualiza e remove gravacao existente', () async {
      final id = await gravacaoRepository.criarGravacao(
        Gravacao(
          usuarioId: usuarioId,
          nome: 'Voz 1',
          caminhoArquivo: '/tmp/voz1.m4a',
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );

      final atualizados = await gravacaoRepository.atualizarGravacao(
        Gravacao(
          id: id,
          usuarioId: usuarioId,
          nome: 'Voz final',
          caminhoArquivo: '/tmp/voz1.m4a',
          dataCriacao: '2026-05-19T10:00:00.000',
          duracaoSegundos: 40,
          status: 'interrompida',
          tamanhoBytes: 512,
          formatoAudio: 'm4a',
        ),
      );

      expect(atualizados, 1);
      final atualizada = await gravacaoRepository.buscarGravacaoPorId(id);
      expect(atualizada!.nome, 'Voz final');
      expect(atualizada.status, 'interrompida');
      expect(atualizada.tamanhoBytes, 512);
      expect(await gravacaoRepository.removerGravacao(id), 1);
      expect(await gravacaoRepository.buscarGravacaoPorId(id), isNull);
    });

    test('listagens ocultam gravacoes marcadas como excluidas', () async {
      final ativaId = await gravacaoRepository.criarGravacao(
        Gravacao(
          usuarioId: usuarioId,
          nome: 'Ativa',
          caminhoArquivo: '/tmp/ativa.m4a',
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );
      final excluidaId = await gravacaoRepository.criarGravacao(
        Gravacao(
          usuarioId: usuarioId,
          nome: 'Excluida',
          caminhoArquivo: '/tmp/excluida.m4a',
          dataCriacao: '2026-05-19T11:00:00.000',
        ),
      );

      expect(await gravacaoRepository.marcarComoExcluida(excluidaId), 1);

      final listadas = await gravacaoRepository.listarGravacoesPorUsuario(
        usuarioId,
      );

      expect(listadas.map((gravacao) => gravacao.id), [ativaId]);
      expect(
        (await gravacaoRepository.buscarGravacaoPorId(excluidaId))!.status,
        GravacaoStatus.excluida,
      );
    });

    test(
      'busca gravacoes por nome e formato mantendo excluidas ocultas',
      () async {
        final refraoId = await gravacaoRepository.criarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            nome: 'Refrao final',
            caminhoArquivo: '/tmp/refrao.m4a',
            dataCriacao: '2026-05-19T10:00:00.000',
            formatoAudio: 'm4a',
          ),
        );
        await gravacaoRepository.criarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            nome: 'Ideia guia',
            caminhoArquivo: '/tmp/guia.wav',
            dataCriacao: '2026-05-19T11:00:00.000',
            formatoAudio: 'wav',
          ),
        );
        final excluidaId = await gravacaoRepository.criarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            nome: 'Refrao descartado',
            caminhoArquivo: '/tmp/descartado.m4a',
            dataCriacao: '2026-05-19T12:00:00.000',
          ),
        );
        await gravacaoRepository.marcarComoExcluida(excluidaId);

        final porNome = await gravacaoRepository.listarGravacoesPorUsuario(
          usuarioId,
          termoBusca: 'refrao',
        );
        final porFormato = await gravacaoRepository.listarGravacoesPorUsuario(
          usuarioId,
          termoBusca: 'wav',
        );

        expect(porNome.map((gravacao) => gravacao.id), [refraoId]);
        expect(porFormato.map((gravacao) => gravacao.nome), ['Ideia guia']);
      },
    );

    test('atualizar gravacao sem id falha explicitamente', () async {
      expect(
        () => gravacaoRepository.atualizarGravacao(
          Gravacao(
            usuarioId: usuarioId,
            nome: 'Sem id',
            caminhoArquivo: '/tmp/sem-id.m4a',
            dataCriacao: '2026-05-19T10:00:00.000',
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
