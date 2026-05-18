import 'package:flutter/material.dart';

import '../../repositories/configuracao_app_repository.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._internal();

  static final AppThemeController instance = AppThemeController._internal();

  bool _temaEscuro = false;

  ThemeMode get themeMode => _temaEscuro ? ThemeMode.dark : ThemeMode.light;

  Future<void> carregarTemaPersistido() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();
    _temaEscuro = configuracao.temaEscuro;
  }

  Future<void> definirTemaEscuro(bool ativo) async {
    if (_temaEscuro == ativo) {
      return;
    }

    _temaEscuro = ativo;
    notifyListeners();
  }
}
