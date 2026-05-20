import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/repositories/comando_personalizado_repository.dart';
import 'package:app_voz/repositories/configuracao_app_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_utils.dart';

void main() {
  const databaseName = 'settings_custom_command_repository_test.db';
  late UsuarioRepository usuarioRepository;
  late ConfiguracaoAppRepository configuracaoRepository;
  late ComandoPersonalizadoRepository comandoRepository;
  late int usuarioId;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    usuarioRepository = UsuarioRepository.instance;
    configuracaoRepository = ConfiguracaoAppRepository.instance;
    comandoRepository = ComandoPersonalizadoRepository.instance;
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

  group('ConfiguracaoAppRepository', () {
    test('busca configuracao padrao criada pelo banco', () async {
      final configuracao = await configuracaoRepository.buscarConfiguracao();

      expect(configuracao.id, 1);
      expect(configuracao.comandosVozAtivos, isTrue);
      expect(configuracao.escutaContinua, isTrue);
      expect(configuracao.temaEscuro, isFalse);
      expect(configuracao.tempoSilencioSegundos, 6);
    });

    test(
      'concluir primeira execucao sincroniza voz e escuta continua',
      () async {
        await configuracaoRepository.concluirPrimeiraExecucao(
          comandosVozAtivos: false,
        );

        final configuracao = await configuracaoRepository.buscarConfiguracao();

        expect(configuracao.primeiraExecucaoConcluida, isTrue);
        expect(configuracao.comandosVozAtivos, isFalse);
        expect(configuracao.escutaContinua, isFalse);
      },
    );

    test('atualizadores preservam demais campos da configuracao', () async {
      await configuracaoRepository.atualizarFeedbackSonoro(true);
      await configuracaoRepository.atualizarParadaSilencio(false);
      await configuracaoRepository.atualizarTempoSilencio(9);
      await configuracaoRepository.atualizarTemaEscuro(true);

      final configuracao = await configuracaoRepository.buscarConfiguracao();

      expect(configuracao.feedbackSonoro, isTrue);
      expect(configuracao.paradaSilencio, isFalse);
      expect(configuracao.tempoSilencioSegundos, 9);
      expect(configuracao.temaEscuro, isTrue);
      expect(configuracao.comandosVozAtivos, isTrue);
    });
  });

  group('ComandoPersonalizadoRepository', () {
    test('salva, lista e filtra comandos ativos por usuario', () async {
      final ativoId = await comandoRepository.salvar(
        ComandoPersonalizado(
          usuarioId: usuarioId,
          frase: 'abrir estudio',
          tipoComando: 'abrir_editor',
          ativo: true,
          dataCriacao: '2026-05-19T11:00:00.000',
        ),
      );
      await comandoRepository.salvar(
        ComandoPersonalizado(
          usuarioId: usuarioId,
          frase: 'modo silencioso',
          tipoComando: 'desativar_feedback_sonoro',
          ativo: false,
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );

      final todos = await comandoRepository.listarPorUsuario(usuarioId);
      final ativos = await comandoRepository.listarAtivosPorUsuario(usuarioId);

      expect(todos.map((comando) => comando.frase), [
        'abrir estudio',
        'modo silencioso',
      ]);
      expect(ativos, hasLength(1));
      expect(ativos.first.id, ativoId);
    });

    test('alterna ativo e exclui comando personalizado', () async {
      final id = await comandoRepository.salvar(
        ComandoPersonalizado(
          usuarioId: usuarioId,
          frase: 'abrir estudio',
          tipoComando: 'abrir_editor',
          ativo: true,
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );

      await comandoRepository.alternarAtivo(id: id, ativo: false);
      expect(
        await comandoRepository.listarAtivosPorUsuario(usuarioId),
        isEmpty,
      );

      await comandoRepository.excluir(id);
      expect(await comandoRepository.listarPorUsuario(usuarioId), isEmpty);
    });

    test('substitui comando por frase unica no mesmo usuario', () async {
      await comandoRepository.salvar(
        ComandoPersonalizado(
          usuarioId: usuarioId,
          frase: 'abrir estudio',
          tipoComando: 'abrir_editor',
          ativo: true,
          dataCriacao: '2026-05-19T10:00:00.000',
        ),
      );
      await comandoRepository.salvar(
        ComandoPersonalizado(
          usuarioId: usuarioId,
          frase: 'abrir estudio',
          tipoComando: 'abrir_dashboard',
          ativo: true,
          dataCriacao: '2026-05-19T11:00:00.000',
        ),
      );

      final comandos = await comandoRepository.listarPorUsuario(usuarioId);

      expect(comandos, hasLength(1));
      expect(comandos.first.tipoComando, 'abrir_dashboard');
    });
  });
}
