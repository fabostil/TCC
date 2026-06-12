import 'package:app_voz/features/dashboard/controllers/dashboard_controller.dart';
import 'package:app_voz/features/dashboard/services/dashboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardController', () {
    test('carrega dashboard e atualiza estado', () async {
      final service = FakeDashboardService(data: _dashboardData());
      final controller = DashboardController(dashboardService: service);

      await controller.load(7);

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isNull);
      expect(controller.state.data, isNotNull);
      expect(controller.state.data!.totalProjetos, 2);
      expect(service.lastUserId, 7);

      controller.dispose();
    });

    test('expõe erro quando usuario nao possui id', () async {
      final controller = DashboardController(
        dashboardService: FakeDashboardService(data: _dashboardData()),
      );

      await controller.load(null);

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, contains('Usuario sem identificacao'));
      expect(controller.state.data, isNull);

      controller.dispose();
    });

    test('expõe erro quando service falha', () async {
      final controller = DashboardController(
        dashboardService: FakeDashboardService(error: Exception('db offline')),
      );

      await controller.load(7);

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, contains('Nao foi possivel carregar'));
      expect(controller.state.data, isNull);

      controller.dispose();
    });
  });
}

DashboardData _dashboardData() {
  return const DashboardData(
    totalProjetos: 2,
    totalGravacoes: 3,
    duracaoTotalSegundos: 120,
    comandosReconhecidos: 4,
    comandosNaoReconhecidos: 1,
    eventosRecentes: [],
    acoesPorTipo: [],
    ultimaGravacao: null,
    insights: [],
  );
}

class FakeDashboardService extends DashboardService {
  FakeDashboardService({this.data, this.error});

  final DashboardData? data;
  final Object? error;
  int? lastUserId;

  @override
  Future<DashboardData> carregar(int usuarioId) async {
    lastUserId = usuarioId;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return data!;
  }
}
