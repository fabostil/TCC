import '../../../models/dashboard_action_metric.dart';
import '../../../models/gravacao.dart';
import '../../../models/historico_acao.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/gravacao_repository.dart';
import '../../../repositories/historico_repository.dart';
import '../../../repositories/projeto_repository.dart';

class DashboardService {
  DashboardService({
    ProjetoRepository? projetoRepository,
    GravacaoRepository? gravacaoRepository,
    HistoricoRepository? historicoRepository,
    ComandoVozRepository? comandoVozRepository,
  }) : _projetoRepository = projetoRepository ?? ProjetoRepository.instance,
       _gravacaoRepository = gravacaoRepository ?? GravacaoRepository.instance,
       _historicoRepository =
           historicoRepository ?? HistoricoRepository.instance,
       _comandoVozRepository =
           comandoVozRepository ?? ComandoVozRepository.instance;

  final ProjetoRepository _projetoRepository;
  final GravacaoRepository _gravacaoRepository;
  final HistoricoRepository _historicoRepository;
  final ComandoVozRepository _comandoVozRepository;

  Future<DashboardData> carregar(int usuarioId) async {
    final resultados = await Future.wait([
      _projetoRepository.listarProjetosPorUsuario(usuarioId),
      _gravacaoRepository.listarGravacoesPorUsuario(usuarioId),
      _comandoVozRepository.contarPorStatus(
        usuarioId: usuarioId,
        statusReconhecimento: 'reconhecido',
      ),
      _comandoVozRepository.contarPorStatus(
        usuarioId: usuarioId,
        statusReconhecimento: 'nao_reconhecido',
      ),
      _historicoRepository.listarPorUsuario(usuarioId, limite: 6),
      _historicoRepository.contarAcoesPorTipo(usuarioId),
    ]);

    final gravacoes = resultados[1] as List<Gravacao>;

    return DashboardData(
      totalProjetos: (resultados[0] as List).length,
      totalGravacoes: gravacoes.length,
      duracaoTotalSegundos: gravacoes.fold(
        0,
        (total, gravacao) => total + gravacao.duracaoSegundos,
      ),
      comandosReconhecidos: resultados[2] as int,
      comandosNaoReconhecidos: resultados[3] as int,
      eventosRecentes: resultados[4] as List<HistoricoAcao>,
      acoesPorTipo: resultados[5] as List<DashboardActionMetric>,
      ultimaGravacao: gravacoes.isEmpty ? null : gravacoes.first,
    );
  }
}

class DashboardData {
  final int totalProjetos;
  final int totalGravacoes;
  final int duracaoTotalSegundos;
  final int comandosReconhecidos;
  final int comandosNaoReconhecidos;
  final List<HistoricoAcao> eventosRecentes;
  final List<DashboardActionMetric> acoesPorTipo;
  final Gravacao? ultimaGravacao;

  const DashboardData({
    required this.totalProjetos,
    required this.totalGravacoes,
    required this.duracaoTotalSegundos,
    required this.comandosReconhecidos,
    required this.comandosNaoReconhecidos,
    required this.eventosRecentes,
    required this.acoesPorTipo,
    required this.ultimaGravacao,
  });

  bool get estaVazio =>
      totalProjetos == 0 &&
      totalGravacoes == 0 &&
      comandosReconhecidos == 0 &&
      comandosNaoReconhecidos == 0 &&
      eventosRecentes.isEmpty &&
      acoesPorTipo.isEmpty;

  int get totalComandos => comandosReconhecidos + comandosNaoReconhecidos;
}
