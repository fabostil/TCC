import 'dart:io';

import '../../../models/gravacao.dart';
import '../../../models/projeto.dart';
import '../../../repositories/gravacao_repository.dart';
import '../../../repositories/projeto_repository.dart';

class RecordingFileInfo {
  const RecordingFileInfo({
    required this.exists,
    required this.sizeBytes,
    required this.path,
  });

  final bool exists;
  final int sizeBytes;
  final String path;
}

class RecordingDetails {
  const RecordingDetails({
    required this.gravacao,
    required this.fileInfo,
    this.projeto,
  });

  final Gravacao gravacao;
  final Projeto? projeto;
  final RecordingFileInfo fileInfo;
}

class RecordingManagementService {
  const RecordingManagementService({
    this.gravacaoRepository,
    this.projetoRepository,
  });

  final GravacaoRepository? gravacaoRepository;
  final ProjetoRepository? projetoRepository;

  GravacaoRepository get _gravacoes =>
      gravacaoRepository ?? GravacaoRepository.instance;
  ProjetoRepository get _projetos =>
      projetoRepository ?? ProjetoRepository.instance;

  Future<RecordingDetails?> loadDetails(int gravacaoId) async {
    final gravacao = await _gravacoes.buscarGravacaoPorId(gravacaoId);
    if (gravacao == null) {
      return null;
    }

    Projeto? projeto;
    final projetoId = gravacao.projetoId;
    if (projetoId != null) {
      projeto = await _projetos.buscarProjetoPorId(projetoId);
    }

    return RecordingDetails(
      gravacao: gravacao,
      projeto: projeto,
      fileInfo: await getFileInfo(gravacao),
    );
  }

  Future<RecordingFileInfo> getFileInfo(Gravacao gravacao) async {
    final file = File(gravacao.caminhoArquivo);
    final exists = await file.exists();

    return RecordingFileInfo(
      exists: exists,
      sizeBytes: exists ? await file.length() : 0,
      path: gravacao.caminhoArquivo,
    );
  }

  Future<Gravacao> renameRecording({
    required Gravacao gravacao,
    required String novoNome,
    required List<Gravacao> gravacoesRelacionadas,
  }) async {
    if (gravacao.id == null) {
      throw ArgumentError('Gravacao sem id nao pode ser renomeada.');
    }

    final nomeFinal = _uniqueName(
      novoNome,
      gravacoesRelacionadas: gravacoesRelacionadas,
      ignorarId: gravacao.id,
    );

    final atualizada = Gravacao(
      id: gravacao.id,
      usuarioId: gravacao.usuarioId,
      projetoId: gravacao.projetoId,
      nome: nomeFinal,
      caminhoArquivo: gravacao.caminhoArquivo,
      dataCriacao: gravacao.dataCriacao,
      duracaoSegundos: gravacao.duracaoSegundos,
    );

    await _gravacoes.atualizarGravacao(atualizada);
    return atualizada;
  }

  Future<void> deleteRecording(Gravacao gravacao) async {
    if (gravacao.id == null) {
      throw ArgumentError('Gravacao sem id nao pode ser excluida.');
    }

    await _gravacoes.removerGravacao(gravacao.id!);

    final file = File(gravacao.caminhoArquivo);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _uniqueName(
    String nomeBase, {
    required List<Gravacao> gravacoesRelacionadas,
    int? ignorarId,
  }) {
    final base = nomeBase.trim();
    if (base.isEmpty) {
      throw ArgumentError('Nome da gravacao nao pode ficar vazio.');
    }

    final nomesExistentes = gravacoesRelacionadas
        .where((gravacao) => gravacao.id != ignorarId)
        .map((gravacao) => _normalize(gravacao.nome))
        .toSet();

    var candidato = base;
    var contador = 1;
    while (nomesExistentes.contains(_normalize(candidato))) {
      candidato = '$base$contador';
      contador++;
    }

    return candidato;
  }

  String _normalize(String value) {
    final lower = value.toLowerCase().trim();
    final withoutAccents = lower
        .replaceAll(RegExp('[\\u00e1\\u00e0\\u00e2\\u00e3\\u00e4]'), 'a')
        .replaceAll(RegExp('[\\u00e9\\u00e8\\u00ea\\u00eb]'), 'e')
        .replaceAll(RegExp('[\\u00ed\\u00ec\\u00ee\\u00ef]'), 'i')
        .replaceAll(RegExp('[\\u00f3\\u00f2\\u00f4\\u00f5\\u00f6]'), 'o')
        .replaceAll(RegExp('[\\u00fa\\u00f9\\u00fb\\u00fc]'), 'u')
        .replaceAll('\u00e7', 'c');

    return withoutAccents.replaceAll(RegExp(r'\s+'), ' ');
  }
}
