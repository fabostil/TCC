import 'package:flutter/foundation.dart';

import '../services/dashboard_service.dart';

class DashboardState {
  final bool loading;
  final String? error;
  final DashboardData? data;

  const DashboardState({
    required this.loading,
    required this.error,
    required this.data,
  });

  const DashboardState.initial() : loading = true, error = null, data = null;

  DashboardState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    DashboardData? data,
  }) {
    return DashboardState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      data: data ?? this.data,
    );
  }
}

class DashboardController extends ChangeNotifier {
  DashboardController({DashboardService? dashboardService})
    : _dashboardService = dashboardService ?? DashboardService();

  final DashboardService _dashboardService;

  DashboardState _state = const DashboardState.initial();

  DashboardState get state => _state;

  Future<void> load(int? usuarioId) async {
    if (usuarioId == null) {
      _setState(
        _state.copyWith(
          loading: false,
          error: 'Usuario sem identificacao para carregar o dashboard.',
        ),
      );
      return;
    }

    _setState(_state.copyWith(loading: true, clearError: true));

    try {
      final dashboard = await _dashboardService.carregar(usuarioId);
      _setState(_state.copyWith(loading: false, data: dashboard));
    } catch (e) {
      _setState(
        _state.copyWith(
          loading: false,
          error: 'Nao foi possivel carregar o dashboard: $e',
        ),
      );
    }
  }

  void _setState(DashboardState nextState) {
    _state = nextState;
    notifyListeners();
  }
}
