import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    final gravacoes = await _gravacoes.listarGravacoesPorUsuario(
      usuarioId,
      termoBusca: termoBusca,
      status: status,
    );
    return _syncMany(gravacoes);
  }

  Future<List<Gravacao>> listByProjectWithFileState(
    int projetoId, {
    String? termoBusca,
    String? status,
  }) async {
    final gravacoes = await _gravacoes.listarGravacoesPorProjeto(
      projetoId,
      termoBusca: termoBusca,
      status: status,
    );
    return _syncMany(gravacoes);
  }

  Future<Gravacao> createCompletedRecording({
    required int usuarioId,
    required int? projetoId,
    required String nome,
    required String caminhoArquivo,
    required DateTime dataCriacao,
    required int duracaoSegundos,
  }) async {
    final fileInfo = await getFileInfoFromPath(caminhoArquivo);
    final status = _statusFromFileInfo(fileInfo);
    final gravacao = Gravacao(
      usuarioId: usuarioId,
      projetoId: projetoId,
      nome: nome,
      caminhoArquivo: caminhoArquivo,
      dataCriacao: dataCriacao.toIso8601String(),
      duracaoSegundos: duracaoSegundos,
      status: status,
      tamanhoBytes: fileInfo.sizeBytes,
      formatoAudio: _formatFromPath(caminhoArquivo),
    );

    final id = await _gravacoes.criarGravacao(gravacao);
    final criada = gravacao.copyWith(id: id);
    debugPrint(
      'RecordingManagementService: gravacao criada id=$id '
      'status=${criada.status} tamanho=${criada.tamanhoBytes}',
    );
    return criada;
  }

  Future<RecordingDetails?> loadDetails(int gravacaoId) async {
    final encontrada = await _gravacoes.buscarGravacaoPorId(gravacaoId);
    final gravacao = encontrada == null
        ? null
        : await syncRecordingFileState(encontrada);
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
    return getFileInfoFromPath(gravacao.caminhoArquivo);
  }

  Future<RecordingFileInfo> getFileInfoFromPath(String path) async {
    final file = File(path);
    final exists = await file.exists();

    return RecordingFileInfo(
      exists: exists,
      sizeBytes: exists ? await file.length() : 0,
      path: path,
    );
  }

  Future<Gravacao> syncRecordingFileState(Gravacao gravacao) async {
    if (gravacao.id == null || gravacao.status == GravacaoStatus.excluida) {
      return gravacao;
    }

    final fileInfo = await getFileInfo(gravacao);
    final nextStatus = _statusFromFileInfo(
      fileInfo,
      currentStatus: gravacao.status,
    );
    final nextFormat = _formatFromPath(gravacao.caminhoArquivo);

    final hasChanges =
        gravacao.status != nextStatus ||
        gravacao.tamanhoBytes != fileInfo.sizeBytes ||
        gravacao.formatoAudio != nextFormat;

    if (!hasChanges) {
      return gravacao;
    }

    final updated = gravacao.copyWith(
      status: nextStatus,
      tamanhoBytes: fileInfo.sizeBytes,
      formatoAudio: nextFormat,
    );
    await _gravacoes.atualizarGravacao(updated);
    debugPrint(
      'RecordingManagementService: estado de arquivo sincronizado '
      'id=${updated.id} status=${updated.status} '
      'tamanho=${updated.tamanhoBytes}',
    );
    return updated;
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

    final atualizada = gravacao.copyWith(nome: nomeFinal);

    await _gravacoes.atualizarGravacao(atualizada);
    return atualizada;
  }

  Future<void> deleteRecording(Gravacao gravacao) async {
    if (gravacao.id == null) {
      throw ArgumentError('Gravacao sem id nao pode ser excluida.');
    }

    final file = File(gravacao.caminhoArquivo);
    if (await file.exists()) {
      await file.delete();
    }

    await _gravacoes.marcarComoExcluida(gravacao.id!);
    debugPrint(
      'RecordingManagementService: gravacao marcada como excluida '
      'id=${gravacao.id}',
    );
  }

  Future<List<Gravacao>> _syncMany(List<Gravacao> gravacoes) {
    return Future.wait(gravacoes.map(syncRecordingFileState));
  }

  String _statusFromFileInfo(
    RecordingFileInfo fileInfo, {
    String currentStatus = GravacaoStatus.concluida,
  }) {
    if (!fileInfo.exists) {
      return GravacaoStatus.arquivoAusente;
    }

    if (fileInfo.sizeBytes <= 0) {
      return GravacaoStatus.interrompida;
    }

    if (currentStatus == GravacaoStatus.arquivoAusente) {
      return GravacaoStatus.concluida;
    }

    return currentStatus;
  }

  String _formatFromPath(String path) {
    final extension = p.extension(path).replaceFirst('.', '').trim();
    return extension.isEmpty ? 'audio' : extension.toLowerCase();
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
