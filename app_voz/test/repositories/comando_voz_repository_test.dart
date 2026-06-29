import 'package:app_voz/models/comando_voz.dart';
import 'package:app_voz/repositories/comando_voz_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_utils.dart';

void main() {
  const databaseName = 'comando_voz_repository_test.db';
  late UsuarioRepository usuarioRepository;
  late ComandoVozRepository repository;
  late int usuarioId;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    usuarioRepository = UsuarioRepository.instance;
    repository = ComandoVozRepository.instance;
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

  group('ComandoVozRepository', () {
    test('banco vazio retorna lista vazia e contadores zerados', () async {
      expect(await repository.listarPorUsuario(usuarioId), isEmpty);
      expect(await repository.contarPorUsuario(usuarioId), 0);
      expect(
        await repository.contarPorStatus(
          usuarioId: usuarioId,
          statusReconhecimento: 'reconhecido',
        ),
        0,
      );
    });

    test('registrar trimma campos e persiste mapeamento principal', () async {
      final dataHora = DateTime.parse('2026-06-10T10:00:00.000');

      final id = await repository.registrar(
        usuarioId: usuarioId,
        textoReconhecido: ' iniciar gravacao ',
        tipoComando: ' iniciar_gravacao ',
        statusReconhecimento: ' reconhecido ',
        acaoExecutada: ' gravacao_iniciada ',
        dataHora: dataHora,
      );

      final comandos = await repository.listarPorUsuario(usuarioId);

      expect(comandos, hasLength(1));
      expect(comandos.single.id, id);
      expect(comandos.single.usuarioId, usuarioId);
      expect(comandos.single.textoReconhecido, 'iniciar gravacao');
      expect(comandos.single.tipoComando, 'iniciar_gravacao');
      expect(comandos.single.statusReconhecimento, 'reconhecido');
      expect(comandos.single.acaoExecutada, 'gravacao_iniciada');
      expect(comandos.single.dataHora, dataHora.toIso8601String());
    });

    test('registrarComando persiste acao nula sem alterar campos', () async {
      final id = await repository.registrarComando(
        ComandoVoz(
          usuarioId: usuarioId,
          textoReconhecido: 'comando desconhecido',
          tipoComando: 'desconhecido',
          statusReconhecimento: 'nao_reconhecido',
          dataHora: '2026-06-10T10:00:00.000',
        ),
      );

      final comandos = await repository.listarPorUsuario(usuarioId);

      expect(comandos.single.id, id);
      expect(comandos.single.textoReconhecido, 'comando desconhecido');
      expect(comandos.single.tipoComando, 'desconhecido');
      expect(comandos.single.statusReconhecimento, 'nao_reconhecido');
      expect(comandos.single.acaoExecutada, isNull);
    });

    test('lista por usuario em ordem recente e respeita limite', () async {
      final antigoId = await repository.registrar(
        usuarioId: usuarioId,
        textoReconhecido: 'abrir editor',
        tipoComando: 'abrir_editor',
        statusReconhecimento: 'reconhecido',
        dataHora: DateTime.parse('2026-06-10T09:00:00.000'),
      );
      final recenteId = await repository.registrar(
        usuarioId: usuarioId,
        textoReconhecido: 'abrir dashboard',
        tipoComando: 'abrir_dashboard',
        statusReconhecimento: 'reconhecido',
        dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
      );

      final todos = await repository.listarPorUsuario(usuarioId);
      final limitado = await repository.listarPorUsuario(usuarioId, limite: 1);

      expect(todos.map((comando) => comando.id), [recenteId, antigoId]);
      expect(limitado.map((comando) => comando.id), [recenteId]);
    });

    test('listagem e contadores ficam isolados por usuario', () async {
      final outroUsuarioId = await _criarUsuario(
        usuarioRepository,
        email: 'bia@example.com',
      );

      await repository.registrar(
        usuarioId: usuarioId,
        textoReconhecido: 'iniciar gravacao',
        tipoComando: 'iniciar_gravacao',
        statusReconhecimento: 'reconhecido',
        dataHora: DateTime.parse('2026-06-10T10:00:00.000'),
      );
      await repository.registrar(
        usuarioId: usuarioId,
        textoReconhecido: 'alguma coisa',
        tipoComando: 'desconhecido',
        statusReconhecimento: 'nao_reconhecido',
        dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
      );
      await repository.registrar(
        usuarioId: outroUsuarioId,
        textoReconhecido: 'abrir dashboard',
        tipoComando: 'abrir_dashboard',
        statusReconhecimento: 'reconhecido',
        dataHora: DateTime.parse('2026-06-10T12:00:00.000'),
      );

      final comandos = await repository.listarPorUsuario(usuarioId);

      expect(comandos, hasLength(2));
      expect(comandos.every((comando) => comando.usuarioId == usuarioId), true);
      expect(await repository.contarPorUsuario(usuarioId), 2);
      expect(
        await repository.contarPorStatus(
          usuarioId: usuarioId,
          statusReconhecimento: 'reconhecido',
        ),
        1,
      );
      expect(await repository.contarPorUsuario(outroUsuarioId), 1);
    });

    test(
      'contador por status usa parametro seguro para texto malicioso',
      () async {
        await repository.registrar(
          usuarioId: usuarioId,
          textoReconhecido: 'iniciar gravacao',
          tipoComando: 'iniciar_gravacao',
          statusReconhecimento: 'reconhecido',
          dataHora: DateTime.parse('2026-06-10T10:00:00.000'),
        );
        await repository.registrar(
          usuarioId: usuarioId,
          textoReconhecido: 'texto livre',
          tipoComando: 'desconhecido',
          statusReconhecimento: 'nao_reconhecido',
          dataHora: DateTime.parse('2026-06-10T11:00:00.000'),
        );

        final totalMalicioso = await repository.contarPorStatus(
          usuarioId: usuarioId,
          statusReconhecimento: "' OR 1=1 --",
        );

        expect(totalMalicioso, 0);
        expect(await repository.contarPorUsuario(usuarioId), 2);
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
