import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class OrphanFileSyncResult {
  const OrphanFileSyncResult({
    required this.candidates,
    required this.deleted,
    required this.skipped,
    required this.errors,
  });

  final List<String> candidates;
  final List<String> deleted;
  final List<String> skipped;
  final Map<String, String> errors;

  int get candidateCount => candidates.length;
  int get deletedCount => deleted.length;
  int get skippedCount => skipped.length;
  int get errorCount => errors.length;
}

typedef RecordingsDirectoryProvider = Future<Directory> Function();
typedef RecordingClock = DateTime Function();

class RecordingManagementService {
  RecordingManagementService({
    this.gravacaoRepository,
    this.projetoRepository,
    RecordingsDirectoryProvider? recordingsDirectoryProvider,
    RecordingClock? clock,
    this.orphanMinimumAge = const Duration(hours: 24),
  }) : _recordingsDirectoryProvider =
           recordingsDirectoryProvider ?? _defaultRecordingsDirectory,
       _clock = clock ?? DateTime.now;

  final GravacaoRepository? gravacaoRepository;
  final ProjetoRepository? projetoRepository;
  final RecordingsDirectoryProvider _recordingsDirectoryProvider;
  final RecordingClock _clock;
  final Duration orphanMinimumAge;
  final Map<String, DateTime> _orphanCandidatesFirstSeen = {};
  bool _orphanSyncStarted = false;

  GravacaoRepository get _gravacoes =>
      gravacaoRepository ?? GravacaoRepository.instance;
  ProjetoRepository get _projetos =>
      projetoRepository ?? ProjetoRepository.instance;

  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async {
    _startOrphanFileSync();
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
    _startOrphanFileSync();
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
    _startOrphanFileSync();
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

  Future<OrphanFileSyncResult> syncOrphanFiles() async {
    final candidates = <String>[];
    final deleted = <String>[];
    final skipped = <String>[];
    final errors = <String, String>{};

    Directory recordingsDirectory;
    try {
      recordingsDirectory = await _recordingsDirectoryProvider();
    } catch (error) {
      errors['recordings_directory'] = error.toString();
      debugPrint(
        'RecordingManagementService: falha ao resolver diretorio de '
        'gravacoes: $error',
      );
      return OrphanFileSyncResult(
        candidates: candidates,
        deleted: deleted,
        skipped: skipped,
        errors: errors,
      );
    }

    if (!await recordingsDirectory.exists()) {
      _orphanCandidatesFirstSeen.clear();
      return OrphanFileSyncResult(
        candidates: candidates,
        deleted: deleted,
        skipped: skipped,
        errors: errors,
      );
    }

    final rootPath = _pathKey(recordingsDirectory.path);
    Set<String> activePaths;
    try {
      activePaths = (await _gravacoes.listarCaminhosArquivosAtivos())
          .map(_pathKey)
          .toSet();
    } catch (error) {
      errors['recordings_database'] = error.toString();
      debugPrint(
        'RecordingManagementService: falha ao listar gravacoes ativas '
        'para sync de orfaos: $error',
      );
      return OrphanFileSyncResult(
        candidates: candidates,
        deleted: deleted,
        skipped: skipped,
        errors: errors,
      );
    }
    final seenOrphans = <String>{};

    try {
      await for (final entity in recordingsDirectory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final filePath = entity.path;
        final fileKey = _pathKey(filePath);
        if (!_isManagedAudioFile(filePath) ||
            !_isInsideManagedDirectory(fileKey, rootPath)) {
          skipped.add(filePath);
          continue;
        }

        if (activePaths.contains(fileKey)) {
          _orphanCandidatesFirstSeen.remove(fileKey);
          continue;
        }

        if (_looksLikeTemporaryRecording(filePath)) {
          skipped.add(filePath);
          continue;
        }

        candidates.add(filePath);
        seenOrphans.add(fileKey);
        final firstSeen = _orphanCandidatesFirstSeen.putIfAbsent(
          fileKey,
          _clock,
        );

        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (error) {
          errors[filePath] = error.toString();
          debugPrint(
            'RecordingManagementService: falha ao ler arquivo candidato '
            '$filePath: $error',
          );
          continue;
        }

        final now = _clock();
        final oldEnough = now.difference(stat.modified) >= orphanMinimumAge;
        final alreadyValidated = firstSeen.isBefore(now);
        if (!oldEnough || !alreadyValidated) {
          skipped.add(filePath);
          continue;
        }

        try {
          final stillExists = await entity.exists();
          final latestActivePaths =
              (await _gravacoes.listarCaminhosArquivosAtivos()).map(_pathKey);
          final stillOrphan = !latestActivePaths.contains(fileKey);
          if (stillExists && stillOrphan) {
            await entity.delete();
            deleted.add(filePath);
            _orphanCandidatesFirstSeen.remove(fileKey);
          }
        } catch (error) {
          errors[filePath] = error.toString();
          debugPrint(
            'RecordingManagementService: falha ao deletar arquivo orfao '
            '$filePath: $error',
          );
        }
      }
    } catch (error) {
      errors[recordingsDirectory.path] = error.toString();
      debugPrint(
        'RecordingManagementService: falha ao listar diretorio de gravacoes '
        '${recordingsDirectory.path}: $error',
      );
    }

    _orphanCandidatesFirstSeen.removeWhere(
      (path, _) => !seenOrphans.contains(path),
    );

    if (candidates.isNotEmpty || deleted.isNotEmpty || errors.isNotEmpty) {
      debugPrint(
        'RecordingManagementService: sync de orfaos candidatos='
        '${candidates.length} deletados=${deleted.length} '
        'erros=${errors.length}',
      );
    }

    return OrphanFileSyncResult(
      candidates: candidates,
      deleted: deleted,
      skipped: skipped,
      errors: errors,
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
      throw ArgumentError('Gravação sem id não pode ser renomeada.');
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
      throw ArgumentError('Gravação sem id não pode ser excluída.');
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

  void _startOrphanFileSync() {
    if (_orphanSyncStarted) {
      return;
    }
    _orphanSyncStarted = true;
    unawaited(syncOrphanFiles());
  }

  bool _isManagedAudioFile(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.wav' || extension == '.m4a';
  }

  bool _isInsideManagedDirectory(String fileKey, String rootKey) {
    return fileKey.startsWith('$rootKey${p.separator}');
  }

  bool _looksLikeTemporaryRecording(String path) {
    final name = p.basename(path).toLowerCase();
    return name.endsWith('.tmp') ||
        name.endsWith('.part') ||
        name.contains('.tmp.') ||
        name.contains('_tmp') ||
        name.contains('temp');
  }

  String _pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static Future<Directory> _defaultRecordingsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return Directory(p.join(directory.path, 'gravacoes'));
  }
}
