import 'dart:io';

import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/repositories/gravacao_repository.dart';
import 'package:app_voz/repositories/usuario_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    service = RecordingManagementService(
      recordingsDirectoryProvider: () async => tempDir,
    );
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

  test('gc nao remove arquivos recentes, temporarios ou ativos', () async {
    final activeFile = File('${tempDir.path}/ativa.m4a');
    final recentOrphan = File('${tempDir.path}/recente.wav');
    final tempOrphan = File('${tempDir.path}/gravacao_temp.wav');
    await activeFile.writeAsBytes([1, 2, 3]);
    await recentOrphan.writeAsBytes([4, 5, 6]);
    await tempOrphan.writeAsBytes([7, 8, 9]);

    await service.createCompletedRecording(
      usuarioId: usuarioId,
      projetoId: null,
      nome: 'Ativa',
      caminhoArquivo: activeFile.path,
      dataCriacao: DateTime.parse('2026-05-19T10:00:00.000'),
      duracaoSegundos: 3,
    );

    final result = await service.syncOrphanFiles();

    expect(result.deleted, isEmpty);
    expect(await activeFile.exists(), isTrue);
    expect(await recentOrphan.exists(), isTrue);
    expect(await tempOrphan.exists(), isTrue);
    expect(result.candidates, containsPath(recentOrphan.path));
    expect(result.skipped, containsPath(tempOrphan.path));
  });

  test('gc remove orfao antigo apenas depois de nova validacao', () async {
    var now = DateTime.parse('2026-05-25T12:00:00.000');
    service = RecordingManagementService(
      recordingsDirectoryProvider: () async => tempDir,
      clock: () => now,
    );
    final oldOrphan = File('${tempDir.path}/orfao_antigo.m4a');
    await oldOrphan.writeAsBytes([1, 2, 3]);
    await oldOrphan.setLastModified(now.subtract(const Duration(hours: 25)));

    final firstPass = await service.syncOrphanFiles();

    expect(firstPass.candidates, containsPath(oldOrphan.path));
    expect(firstPass.deleted, isEmpty);
    expect(await oldOrphan.exists(), isTrue);

    now = now.add(const Duration(minutes: 1));
    final secondPass = await service.syncOrphanFiles();

    expect(secondPass.deleted, containsPath(oldOrphan.path));
    expect(await oldOrphan.exists(), isFalse);
  });

  test('gc nunca remove arquivo fora do diretorio controlado', () async {
    final managedOrphan = File('${tempDir.path}/orfao_controlado.wav');
    final outsideDir = await Directory.systemTemp.createTemp(
      'recording_management_outside_',
    );
    addTearDown(() async {
      if (await outsideDir.exists()) {
        await outsideDir.delete(recursive: true);
      }
    });
    final outsideFile = File('${outsideDir.path}/fora.wav');
    await managedOrphan.writeAsBytes([1, 2, 3]);
    await outsideFile.writeAsBytes([4, 5, 6]);
    var now = DateTime.parse('2026-05-25T12:00:00.000');
    await managedOrphan.setLastModified(
      now.subtract(const Duration(hours: 25)),
    );
    await outsideFile.setLastModified(now.subtract(const Duration(hours: 25)));
    service = RecordingManagementService(
      recordingsDirectoryProvider: () async => tempDir,
      clock: () => now,
    );

    await service.syncOrphanFiles();
    now = now.add(const Duration(minutes: 1));
    await service.syncOrphanFiles();

    expect(await managedOrphan.exists(), isFalse);
    expect(await outsideFile.exists(), isTrue);
  });
}

Matcher containsPath(String expectedPath) {
  return contains(predicate<String>((path) => p.equals(path, expectedPath)));
}
