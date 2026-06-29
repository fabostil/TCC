import 'package:app_voz/features/dashboard/services/dashboard_service.dart';
import 'package:app_voz/models/dashboard_action_metric.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/historico_acao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardService.gerarInsightsLocais', () {
    test('recomenda organizar gravacoes quando ainda nao ha projetos', () {
      final insights = DashboardService.gerarInsightsLocais(
        totalProjetos: 0,
        gravacoes: [
          Gravacao(
            usuarioId: 1,
            nome: 'Ideia solta',
            caminhoArquivo: '/tmp/ideia.m4a',
            dataCriacao: '2026-05-19T10:00:00.000',
            duracaoSegundos: 40,
          ),
        ],
        duracaoTotalSegundos: 40,
        comandosReconhecidos: 0,
        comandosNaoReconhecidos: 0,
        eventosRecentes: const [],
        acoesPorTipo: const [],
        agora: DateTime(2026, 5, 19),
      );

      expect(insights, isNotEmpty);
      expect(insights.first.tipo, DashboardInsightType.organizacao);
      expect(insights.first.prioridade, DashboardInsightPriority.alta);
    });

    test('alerta quando muitos comandos nao sao reconhecidos', () {
      final insights = DashboardService.gerarInsightsLocais(
        totalProjetos: 1,
        gravacoes: const [],
        duracaoTotalSegundos: 0,
        comandosReconhecidos: 4,
        comandosNaoReconhecidos: 4,
        eventosRecentes: const [],
        acoesPorTipo: const [],
        agora: DateTime(2026, 5, 19),
      );

      expect(
        insights.any((insight) => insight.tipo == DashboardInsightType.voz),
        isTrue,
      );
      expect(
        insights
            .where((insight) => insight.tipo == DashboardInsightType.voz)
            .first
            .prioridade,
        DashboardInsightPriority.alta,
      );
    });

    test('alerta para arquivos ausentes antes de recomendacoes baixas', () {
      final insights = DashboardService.gerarInsightsLocais(
        totalProjetos: 1,
        gravacoes: [
          Gravacao(
            usuarioId: 1,
            projetoId: 10,
            nome: 'Guia',
            caminhoArquivo: '/tmp/guia.m4a',
            dataCriacao: '2026-05-18T10:00:00.000',
            status: GravacaoStatus.arquivoAusente,
          ),
        ],
        duracaoTotalSegundos: 0,
        comandosReconhecidos: 8,
        comandosNaoReconhecidos: 0,
        eventosRecentes: const [],
        acoesPorTipo: const [
          DashboardActionMetric(tipo: 'gravacao_criada', total: 5),
        ],
        agora: DateTime(2026, 5, 19),
      );

      expect(insights.first.tipo, DashboardInsightType.alerta);
      expect(insights.first.prioridade, DashboardInsightPriority.alta);
      expect(
        insights.any(
          (insight) => insight.titulo == 'Fluxo por voz está consistente',
        ),
        isTrue,
      );
    });

    test('limita a lista a quatro insights', () {
      final insights = DashboardService.gerarInsightsLocais(
        totalProjetos: 0,
        gravacoes: [
          Gravacao(
            usuarioId: 1,
            nome: 'A',
            caminhoArquivo: '/tmp/a.m4a',
            dataCriacao: '2026-05-01T10:00:00.000',
            status: GravacaoStatus.interrompida,
          ),
          Gravacao(
            usuarioId: 1,
            nome: 'B',
            caminhoArquivo: '/tmp/b.m4a',
            dataCriacao: '2026-05-01T11:00:00.000',
            status: GravacaoStatus.arquivoAusente,
          ),
          Gravacao(
            usuarioId: 1,
            nome: 'C',
            caminhoArquivo: '/tmp/c.m4a',
            dataCriacao: '2026-05-01T12:00:00.000',
          ),
        ],
        duracaoTotalSegundos: 30,
        comandosReconhecidos: 7,
        comandosNaoReconhecidos: 4,
        eventosRecentes: [
          HistoricoAcao(
            usuarioId: 1,
            tipo: 'gravacao_criada',
            descricao: 'Criada',
            dataHora: '2026-05-19T10:00:00.000',
          ),
        ],
        acoesPorTipo: const [
          DashboardActionMetric(tipo: 'gravacao_criada', total: 5),
        ],
        agora: DateTime(2026, 5, 19),
      );

      expect(insights, hasLength(4));
    });
  });
}
