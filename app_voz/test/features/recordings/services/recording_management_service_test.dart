import 'dart:io';

import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/repositories/gravacao_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../repositories/repository_test_utils.dart';

void main() {
  const databaseName = 'recording_management_service_test.db';
  late RecordingManagementService service;
  late UsuarioRepository usuarioRepository;
  late GravacaoRepository gravacaoRepository;
  late Directory tempDir;
  late int usuarioId;

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    await useRepositoryTestDatabase(databaseName);
    await resetRepositoryTestDatabase(databaseName);
    tempDir = await Directory.systemTemp.createTemp(
      'recording_management_service_test_',
    );
    service = const RecordingManagementService();
    usuarioRepository = UsuarioRepository.instance;
    gravacaoRepository = GravacaoRepository.instance;

    await usuarioRepository.cadastrarUsuario(
      nome: 'Alex',
      email: 'alex-recording-service@example.com',
      senha: 'abc12345',
    );
    usuarioId = (await usuarioRepository.buscarPorEmail(
      'alex-recording-service@example.com',
    ))!.id!;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await resetRepositoryTestDatabase(databaseName);
  });

  test('cria gravacao com metadados reais do arquivo', () async {
    final file = File('${tempDir.path}/take.m4a');
    await file.writeAsBytes([1, 2, 3, 4]);

    final gravacao = await service.createCompletedRecording(
      usuarioId: usuarioId,
      projetoId: null,
      nome: 'Take',
      caminhoArquivo: file.path,
      dataCriacao: DateTime.parse('2026-05-19T10:00:00.000'),
      duracaoSegundos: 12,
    );

    expect(gravacao.id, isNotNull);
    expect(gravacao.status, GravacaoStatus.concluida);
    expect(gravacao.tamanhoBytes, 4);
    expect(gravacao.formatoAudio, 'm4a');

    final persistida = await gravacaoRepository.buscarGravacaoPorId(
      gravacao.id!,
    );
    expect(persistida!.tamanhoBytes, 4);
    expect(persistida.status, GravacaoStatus.concluida);
  });

  test('persiste formato dinamico a partir do path final wav', () async {
    final file = File('${tempDir.path}/take.wav');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    final gravacao = await service.createCompletedRecording(
      usuarioId: usuarioId,
      projetoId: null,
      nome: 'Take wav',
      caminhoArquivo: file.path,
      dataCriacao: DateTime.parse('2026-05-19T10:00:00.000'),
      duracaoSegundos: 12,
    );

    expect(gravacao.caminhoArquivo.endsWith('.wav'), isTrue);
    expect(gravacao.formatoAudio, 'wav');

    final persistida = await gravacaoRepository.buscarGravacaoPorId(
      gravacao.id!,
    );
    expect(persistida!.caminhoArquivo.endsWith('.wav'), isTrue);
    expect(persistida.formatoAudio, 'wav');
  });

  test('sincroniza arquivo ausente e persiste status diagnostico', () async {
    final gravacaoId = await gravacaoRepository.criarGravacao(
      Gravacao(
        usuarioId: usuarioId,
        nome: 'Arquivo perdido',
        caminhoArquivo: '${tempDir.path}/nao-existe.m4a',
        dataCriacao: '2026-05-19T10:00:00.000',
        duracaoSegundos: 5,
        tamanhoBytes: 123,
      ),
    );
    final gravacao = (await gravacaoRepository.buscarGravacaoPorId(
      gravacaoId,
    ))!;

    final sincronizada = await service.syncRecordingFileState(gravacao);

    expect(sincronizada.status, GravacaoStatus.arquivoAusente);
    expect(sincronizada.tamanhoBytes, 0);
    expect(
      (await gravacaoRepository.buscarGravacaoPorId(gravacaoId))!.status,
      GravacaoStatus.arquivoAusente,
    );
  });

  test(
    'exclusao e logica, remove arquivo fisico e oculta de listagens',
    () async {
      final file = File('${tempDir.path}/delete.m4a');
      await file.writeAsBytes([1, 2, 3]);
      final gravacao = await service.createCompletedRecording(
        usuarioId: usuarioId,
        projetoId: null,
        nome: 'Excluir',
        caminhoArquivo: file.path,
        dataCriacao: DateTime.parse('2026-05-19T10:00:00.000'),
        duracaoSegundos: 3,
      );

      await service.deleteRecording(gravacao);

      expect(await file.exists(), isFalse);
      final persistida = await gravacaoRepository.buscarGravacaoPorId(
        gravacao.id!,
      );
      expect(persistida!.status, GravacaoStatus.excluida);
      expect(
        await gravacaoRepository.listarGravacoesPorUsuario(usuarioId),
        isEmpty,
      );
    },
  );
}
