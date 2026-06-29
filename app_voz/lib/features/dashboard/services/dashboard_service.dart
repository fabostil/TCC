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
    final totalProjetos = (resultados[0] as List).length;
    final comandosReconhecidos = resultados[2] as int;
    final comandosNaoReconhecidos = resultados[3] as int;
    final eventosRecentes = resultados[4] as List<HistoricoAcao>;
    final acoesPorTipo = resultados[5] as List<DashboardActionMetric>;
    final ultimaGravacao = gravacoes.isEmpty ? null : gravacoes.first;
    final duracaoTotalSegundos = gravacoes.fold(
      0,
      (total, gravacao) => total + gravacao.duracaoSegundos,
    );

    return DashboardData(
      totalProjetos: totalProjetos,
      totalGravacoes: gravacoes.length,
      duracaoTotalSegundos: duracaoTotalSegundos,
      comandosReconhecidos: comandosReconhecidos,
      comandosNaoReconhecidos: comandosNaoReconhecidos,
      eventosRecentes: eventosRecentes,
      acoesPorTipo: acoesPorTipo,
      ultimaGravacao: ultimaGravacao,
      insights: gerarInsightsLocais(
        totalProjetos: totalProjetos,
        gravacoes: gravacoes,
        duracaoTotalSegundos: duracaoTotalSegundos,
        comandosReconhecidos: comandosReconhecidos,
        comandosNaoReconhecidos: comandosNaoReconhecidos,
        eventosRecentes: eventosRecentes,
        acoesPorTipo: acoesPorTipo,
        agora: DateTime.now(),
      ),
    );
  }

  static List<DashboardInsight> gerarInsightsLocais({
    required int totalProjetos,
    required List<Gravacao> gravacoes,
    required int duracaoTotalSegundos,
    required int comandosReconhecidos,
    required int comandosNaoReconhecidos,
    required List<HistoricoAcao> eventosRecentes,
    required List<DashboardActionMetric> acoesPorTipo,
    required DateTime agora,
  }) {
    final insights = <DashboardInsight>[];
    final totalGravacoes = gravacoes.length;
    final totalComandos = comandosReconhecidos + comandosNaoReconhecidos;
    final gravacoesSemProjeto = gravacoes
        .where((gravacao) => gravacao.projetoId == null)
        .length;
    final gravacoesInterrompidas = gravacoes
        .where((gravacao) => gravacao.status == GravacaoStatus.interrompida)
        .length;
    final gravacoesComArquivoAusente = gravacoes
        .where((gravacao) => gravacao.status == GravacaoStatus.arquivoAusente)
        .length;

    if (totalProjetos == 0 && totalGravacoes > 0) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.organizacao,
          titulo: 'Organize suas ideias em projetos',
          descricao:
              'Você já tem gravações, mas ainda não criou projetos. Criar projetos ajuda a separar demos, letras e referências.',
          prioridade: DashboardInsightPriority.alta,
        ),
      );
    } else if (gravacoesSemProjeto >= 3) {
      insights.add(
        DashboardInsight(
          tipo: DashboardInsightType.organizacao,
          titulo: 'Revise gravações sem projeto',
          descricao:
              '$gravacoesSemProjeto gravações ainda não estão ligadas a um projeto. Vincular essas ideias melhora a busca e a apresentação.',
          prioridade: DashboardInsightPriority.media,
        ),
      );
    }

    if (totalProjetos > 0 && totalGravacoes == 0) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.producao,
          titulo: 'Comece uma primeira gravação',
          descricao:
              'Você já tem projeto criado. O próximo passo é registrar uma ideia no editor para alimentar o histórico musical.',
          prioridade: DashboardInsightPriority.alta,
        ),
      );
    }

    if (totalGravacoes >= 3 && duracaoTotalSegundos < 60) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.producao,
          titulo: 'Gravações muito curtas',
          descricao:
              'Há várias capturas, mas a duração total ainda é baixa. Vale gravar uma versão guia mais completa da melhor ideia.',
          prioridade: DashboardInsightPriority.media,
        ),
      );
    }

    if (gravacoesInterrompidas > 0) {
      insights.add(
        DashboardInsight(
          tipo: DashboardInsightType.alerta,
          titulo: 'Há gravações interrompidas',
          descricao:
              '$gravacoesInterrompidas gravações terminaram como interrompidas. Confira se precisam ser refeitas ou renomeadas.',
          prioridade: DashboardInsightPriority.media,
        ),
      );
    }

    if (gravacoesComArquivoAusente > 0) {
      insights.add(
        DashboardInsight(
          tipo: DashboardInsightType.alerta,
          titulo: 'Arquivos de áudio ausentes',
          descricao:
              '$gravacoesComArquivoAusente gravações apontam para arquivo ausente. Evite apresentar esses itens antes de revisar.',
          prioridade: DashboardInsightPriority.alta,
        ),
      );
    }

    if (comandosNaoReconhecidos >= 3 &&
        totalComandos > 0 &&
        comandosNaoReconhecidos / totalComandos >= 0.3) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.voz,
          titulo: 'Comandos de voz precisam de ajuste',
          descricao:
              'Muitos comandos não foram reconhecidos. Cadastre frases personalizadas para os comandos que você mais usa.',
          prioridade: DashboardInsightPriority.alta,
        ),
      );
    } else if (comandosReconhecidos >= 5 && comandosNaoReconhecidos == 0) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.voz,
          titulo: 'Fluxo por voz está consistente',
          descricao:
              'Os comandos recentes foram reconhecidos sem falhas registradas. Esse é um bom ponto para testar em aparelho Android.',
          prioridade: DashboardInsightPriority.baixa,
        ),
      );
    }

    final ultimaGravacao = gravacoes.isEmpty ? null : gravacoes.first;
    final dataUltimaGravacao = ultimaGravacao == null
        ? null
        : DateTime.tryParse(ultimaGravacao.dataCriacao);
    if (dataUltimaGravacao != null &&
        agora.difference(dataUltimaGravacao).inDays >= 7) {
      insights.add(
        DashboardInsight(
          tipo: DashboardInsightType.producao,
          titulo: 'Retome uma ideia antiga',
          descricao:
              'A última gravação tem ${agora.difference(dataUltimaGravacao).inDays} dias. Reabrir esse material ajuda a manter continuidade criativa.',
          prioridade: DashboardInsightPriority.media,
        ),
      );
    }

    final tipoMaisFrequente = acoesPorTipo.isEmpty ? null : acoesPorTipo.first;
    if (tipoMaisFrequente != null && tipoMaisFrequente.total >= 5) {
      insights.add(
        DashboardInsight(
          tipo: DashboardInsightType.historico,
          titulo: 'Padrao de uso detectado',
          descricao:
              'A ação mais frequente é "${tipoMaisFrequente.tipo.replaceAll('_', ' ')}" com ${tipoMaisFrequente.total} ocorrências.',
          prioridade: DashboardInsightPriority.baixa,
        ),
      );
    }

    if (insights.isEmpty && eventosRecentes.isNotEmpty) {
      insights.add(
        const DashboardInsight(
          tipo: DashboardInsightType.historico,
          titulo: 'Atividade recente registrada',
          descricao:
              'O histórico já tem eventos suficientes para acompanhar sua rotina de criação dentro do app.',
          prioridade: DashboardInsightPriority.baixa,
        ),
      );
    }

    return insights.take(4).toList();
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
  final List<DashboardInsight> insights;

  const DashboardData({
    required this.totalProjetos,
    required this.totalGravacoes,
    required this.duracaoTotalSegundos,
    required this.comandosReconhecidos,
    required this.comandosNaoReconhecidos,
    required this.eventosRecentes,
    required this.acoesPorTipo,
    required this.ultimaGravacao,
    required this.insights,
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

enum DashboardInsightType { producao, organizacao, voz, alerta, historico }

enum DashboardInsightPriority { alta, media, baixa }

class DashboardInsight {
  final DashboardInsightType tipo;
  final String titulo;
  final String descricao;
  final DashboardInsightPriority prioridade;

  const DashboardInsight({
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.prioridade,
  });
}
