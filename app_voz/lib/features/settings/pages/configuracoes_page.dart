import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/user_facing_messages.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/comando_personalizado.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../editor/pages/editor_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/services/command_service.dart';
import '../../onboarding/pages/app_entry_gate.dart';
import '../../voices/services/auth_session_service.dart';
import '../../voices/services/custom_command_service.dart';
import '../../voices/services/voice_permission_service.dart';
import '../../voices/widgets/voice_command_help_dialog.dart';
import '../controllers/settings_controller.dart';

const int _minCommandPhraseLength = 3;
const int _maxCommandPhraseLength = 120;

String? _validateCommandPhrase(String? value) {
  final trimmed = value?.trim() ?? '';
  final normalized = CustomCommandRules.normalizePhrase(trimmed);
  if (trimmed.isEmpty) {
    return 'Informe a frase do comando.';
  }
  if (normalized.isEmpty) {
    return 'Informe uma frase válida para o comando.';
  }
  if (normalized.length < _minCommandPhraseLength) {
    return 'A frase deve ter pelo menos 3 caracteres.';
  }
  if (trimmed.length > _maxCommandPhraseLength) {
    return 'A frase deve ter no máximo 120 caracteres.';
  }
  return null;
}

class ConfiguracoesPage extends StatefulWidget {
  final Usuario? usuario;
  @visibleForTesting
  final bool enableVoiceListening;
  @visibleForTesting
  final SettingsController? settingsController;

  const ConfiguracoesPage({
    super.key,
    this.usuario,
    @visibleForTesting this.enableVoiceListening = true,
    @visibleForTesting this.settingsController,
  });

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage>
    with ContextualVoiceListeningMixin<ConfiguracoesPage> {
  final VoicePermissionService _voicePermissionService =
      const VoicePermissionService();
  late final SettingsController _settingsController;
  final _customCommandFormKey = GlobalKey<FormState>();
  final TextEditingController _frasePersonalizadaController =
      TextEditingController();
  final ScrollController _voiceScrollController = ScrollController();
  VoicePermissionResult? _ultimoResultadoPermissao;
  String _tipoComandoPersonalizado =
      CustomCommandCatalog.actions.first.tipoComando;
  int? _tempoSilencioVisual;
  double? _limiarSilencioVisual;
  final GlobalKey _customCommandFormKey2 = GlobalKey();
  final GlobalKey _silenceSectionKey = GlobalKey();
  bool _salvandoComandoPersonalizado = false;
  bool _alterandoControleVoz = false;
  int? _alternandoComandoPersonalizadoId;
  int? _excluindoComandoPersonalizadoId;
  bool _aguardandoConfirmacaoLogout = false;
  bool _fazendoLogout = false;

  SettingsState get _settingsState => _settingsController.state;

  @override
  String get voiceOwnerId => VoicePageOwners.configuracoes;

  @override
  int? get voiceUsuarioId => widget.usuario?.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando de configuração...';

  @override
  bool get voiceHandlesGlobalCommands => false;

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  void initState() {
    super.initState();
    _settingsController = widget.settingsController ?? SettingsController();
    _settingsController.addListener(_onSettingsStateChanged);
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.settings,
      goHome: _handleIrParaHome,
      openProjects: _handleAbrirProjetosGlobal,
      openRecordings: _handleAbrirGravacoesGlobal,
      openDashboard: _handleAbrirDashboardGlobal,
      openHistory: _handleAbrirHistoricoGlobal,
      openEditor: _handleAbrirEditorGlobal,
      openNewProject: _handleAbrirNovoProjetoGlobal,
      goBack: _handleVoltarGlobal,
    );
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchSettingsVoice,
    );
    _carregarConfiguracao();
    if (widget.enableVoiceListening) scheduleVoiceListeningOnFirstFrame();
  }

  void _onSettingsStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarConfiguracao() async {
    await _settingsController.load(usuarioId: widget.usuario?.id);
    final configuracao = _settingsState.configuration;
    if (configuracao == null || !mounted) {
      return;
    }
    syncVoiceConfigFlags(configuracao);
    if (widget.enableVoiceListening) await startContinuousVoiceListeningIfActive();
  }

  Future<void> _salvar(ConfiguracaoApp configuracao) async {
    await _settingsController.saveConfiguration(configuracao);
  }

  Future<void> _salvarTempoSilencio(
    ConfiguracaoApp configuracao,
    double value,
  ) async {
    final segundos = value.round();
    voiceSetState(() {
      _tempoSilencioVisual = segundos;
    });
    await _salvar(configuracao.copyWith(tempoSilencioSegundos: segundos));
    if (!mounted) {
      return;
    }
    voiceSetState(() {
      _tempoSilencioVisual = null;
    });
  }

  Future<void> _salvarComandoPersonalizado() async {
    if (_customCommandFormKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _salvandoComandoPersonalizado = true;
    });

    try {
      await _settingsController.saveCustomCommand(
        usuarioId: widget.usuario?.id,
        phrase: _frasePersonalizadaController.text,
        commandType: _tipoComandoPersonalizado,
      );
      if (!mounted) {
        return;
      }

      _frasePersonalizadaController.clear();
      _atualizarStatus(
        'Comando personalizado salvo. Você já pode usar essa frase por voz.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _atualizarStatus(
        UserFacingMessages.error(e, fallback: UserFacingMessages.dataSaveError),
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvandoComandoPersonalizado = false;
        });
      }
    }
  }

  Future<void> _alternarComandoPersonalizado(
    ComandoPersonalizado comando,
    bool ativo,
  ) async {
    final id = comando.id;
    if (id == null) {
      return;
    }

    setState(() {
      _alternandoComandoPersonalizadoId = id;
    });

    try {
      await _settingsController.toggleCustomCommand(
        comando,
        ativo,
        usuarioId: widget.usuario?.id,
      );
    } finally {
      if (mounted) {
        setState(() {
          _alternandoComandoPersonalizadoId = null;
        });
      }
    }
  }

  Future<void> _excluirComandoPersonalizado(
    ComandoPersonalizado comando,
  ) async {
    final id = comando.id;
    if (id == null) {
      return;
    }

    setState(() {
      _excluindoComandoPersonalizadoId = id;
    });

    try {
      await _settingsController.deleteCustomCommand(
        comando,
        usuarioId: widget.usuario?.id,
      );
      if (!mounted) {
        return;
      }

      _atualizarStatus('Comando personalizado removido.');
    } finally {
      if (mounted) {
        setState(() {
          _excluindoComandoPersonalizadoId = null;
        });
      }
    }
  }

  Future<void> _salvarTemaEscuro(bool ativo) async {
    final configuracao = _settingsState.configuration;
    if (configuracao == null) {
      return;
    }

    await _settingsController.setDarkTheme(ativo);
  }

  Future<void> _salvarLimiarSilencio(
    ConfiguracaoApp configuracao,
    double value,
  ) async {
    final clamped = value.clamp(
      ConfiguracaoApp.limiarSilencioDbMin,
      ConfiguracaoApp.limiarSilencioDbMax,
    );
    voiceSetState(() {
      _limiarSilencioVisual = null;
    });
    await _salvar(configuracao.copyWith(limiarSilencioDb: clamped));
  }

  void _irParaFormularioComandoPersonalizado({
    String? frase,
    String? tipoComando,
  }) {
    if (frase != null && frase.isNotEmpty) {
      _frasePersonalizadaController.text = frase;
    }
    if (tipoComando != null) {
      final action = CustomCommandCatalog.findByTipo(tipoComando);
      if (action != null) {
        voiceSetState(() {
          _tipoComandoPersonalizado = tipoComando;
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _customCommandFormKey2.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
      }
    });
  }

  void _scrollToSilenceSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _silenceSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
        );
      }
    });
  }

  bool _isNavToSilenceSection(String normalized) {
    const navigating = [
      'ir para parada automatica',
      'ir para parada por silencio',
      'ir para silencio',
      'ir para configuracoes de silencio',
      'mostrar parada automatica',
      'mostrar parada por silencio',
      'ver parada automatica',
      'ver parada por silencio',
    ];
    if (navigating.any((p) => normalized == p || normalized.contains(p))) {
      return true;
    }
    const standalone = [
      'parada automatica',
      'automatico por silencio',
      'configuracoes de silencio',
    ];
    return standalone.any((p) => normalized == p);
  }

  Future<void> _abrirAjudaComandosConfiguracoes() {
    return showVoiceCommandHelpDialog(
      context,
      contextType: VoiceCommandHelpContext.settings,
    );
  }

  Future<void> _alterarControleVoz(bool ativo) async {
    final configuracao = _settingsState.configuration;
    if (configuracao == null) {
      return;
    }

    setState(() {
      _alterandoControleVoz = true;
    });

    try {
      if (!ativo) {
        await _salvar(
          configuracao.copyWith(
            comandosVozAtivos: false,
            escutaContinua: false,
          ),
        );
        await suspendContextualVoiceListening(keepManualPause: true);
        if (!mounted) {
          return;
        }

        _atualizarStatus('Controle por voz pausado.');
        return;
      }

      final permissao = await _voicePermissionService.requestMicrophone();
      if (permissao != VoicePermissionResult.granted) {
        await _salvar(
          configuracao.copyWith(
            comandosVozAtivos: false,
            escutaContinua: false,
          ),
        );
        if (!mounted) {
          return;
        }

        setState(() {
          _ultimoResultadoPermissao = permissao;
        });
        _atualizarStatus(
          permissao == VoicePermissionResult.permanentlyDenied
              ? 'Microfone bloqueado nas configurações do Android.'
              : 'Permita o uso do microfone para controlar o app por voz.',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _ultimoResultadoPermissao = VoicePermissionResult.granted;
      });
      await _salvar(
        configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
      );
      if (!mounted) {
        return;
      }

      syncVoiceConfigFlags(
        configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
      );
      voiceParadaManual = false;
      _atualizarStatus('Controle por voz ativado.');
      scheduleVoiceContinuousRestart();
    } finally {
      if (mounted) {
        setState(() {
          _alterandoControleVoz = false;
        });
      }
    }
  }

  Future<void> _sairDaContaLogout() async {
    if (_fazendoLogout) return;
    setState(() {
      _fazendoLogout = true;
      _aguardandoConfirmacaoLogout = false;
    });
    try {
      await suspendContextualVoiceListening();
      await AuthSessionService.instance.logout();
    } catch (_) {
      if (mounted) {
        setState(() {
          _fazendoLogout = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui sair da conta. Tente novamente.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppEntryGate()),
      (route) => false,
    );
  }

  Future<void> _handleLogoutButton() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Você será desconectado do Touchless.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_logout_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sairDaContaLogout();
  }

  // Returns -dB value when the text contains a recognizable silence threshold
  // like "menos trinta", "menos 30", "sensibilidade 40" etc.
  double? _extrairLimiarDb(String text) {
    const wordToNumber = {
      'dez': 10, 'vinte': 20, 'trinta': 30,
      'quarenta': 40, 'cinquenta': 50, 'sessenta': 60,
    };

    // Explicit digit: "menos 30", "limiar 40", "-30"
    final digitMatch = RegExp(
      r'(?:menos\s*|-\s*)([0-9]+)|limiar\s+([0-9]+)|sensibilidade\s+([0-9]+)',
    ).firstMatch(text);
    if (digitMatch != null) {
      final raw =
          digitMatch.group(1) ?? digitMatch.group(2) ?? digitMatch.group(3);
      final n = int.tryParse(raw ?? '');
      if (n != null && n >= 10 && n <= 60) {
        return -n.toDouble();
      }
    }

    // Word: "menos trinta", "trinta decibeis"
    for (final entry in wordToNumber.entries) {
      if (text.contains('menos ${entry.key}') ||
          text.contains('${entry.key} decibei')) {
        return -entry.value.toDouble();
      }
    }

    return null;
  }

  // Tries to extract frase + tipoComando from a "criar comando X para Y" utterance.
  ({String frase, String? tipoComando}) _extrairComandoPersonalizado(
    String text,
  ) {
    // Pattern: "criar comando [frase] para [ação]"
    final match = RegExp(
      r'criar (?:um )?comando (?:personalizado )?(.+?) para (.+)',
    ).firstMatch(text);
    if (match != null) {
      final frase = match.group(1)?.trim() ?? '';
      final acaoRaw = match.group(2)?.trim() ?? '';
      final acao = CustomCommandCatalog.actions.firstWhere(
        (a) => a.label.toLowerCase().contains(acaoRaw) ||
            a.tipoComando.contains(acaoRaw.replaceAll(' ', '_')),
        orElse: () => CustomCommandCatalog.actions.first,
      );
      return (
        frase: frase,
        tipoComando: frase.isNotEmpty ? acao.tipoComando : '',
      );
    }
    return (frase: '', tipoComando: null);
  }

  Future<VoiceCommandPageResult> _dispatchSettingsVoice(
    CommandResult resultado,
  ) async {
    final configuracao = _settingsState.configuration;
    if (configuracao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Configuração ainda carregando.',
      );
    }

    // Handle silence threshold voice commands before the main switch so we
    // don't need a new VoiceCommandType (avoids updating every page dispatcher).
    final rawText = resultado.normalizedText;
    {
      final normalized = rawText.trim();
      final isThresholdCommand = normalized.contains('limiar') ||
          normalized.contains('sensibilidade') ||
          (normalized.contains('silencio') &&
              (normalized.contains('decibei') ||
                  normalized.contains('menos') ||
                  RegExp(r'\d').hasMatch(normalized)));
      if (isThresholdCommand) {
        final db = _extrairLimiarDb(normalized);
        if (db != null) {
          await _salvarLimiarSilencio(configuracao, db);
          if (!mounted) {
            return VoiceCommandPageResult.handled(restartListening: false);
          }
          _atualizarStatus('Limiar de silêncio definido para ${db.toInt()} dB.');
          return VoiceCommandPageResult.handled();
        }
        _atualizarStatus(
          'Diga o valor em dB, por exemplo: limiar menos trinta.',
        );
        return VoiceCommandPageResult.handled();
      }
    }

    // Scroll-to-section shortcuts (no VoiceCommandType needed)
    if (_isNavToSilenceSection(rawText.trim())) {
      _scrollToSilenceSection();
      return VoiceCommandPageResult.handled(
        message: 'Seção de parada por silêncio.',
      );
    }

    switch (resultado.type) {
      case VoiceCommandType.ativarControleVoz:
        await _alterarControleVoz(true);
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarControleVoz:
        await _alterarControleVoz(false);
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.ativarEscutaContinua:
        await _salvar(
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
        );
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        syncVoiceConfigFlags(
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
        );
        _atualizarStatus('Escuta contínua ativada.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarEscutaContinua:
        await _salvar(configuracao.copyWith(escutaContinua: false));
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        syncVoiceConfigFlags(configuracao.copyWith(escutaContinua: false));
        _atualizarStatus('Escuta contínua desativada.');
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.ativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: true));
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Feedback sonoro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: false));
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Feedback sonoro desativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.ativarTemaEscuro:
        await _salvarTemaEscuro(true);
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Tema escuro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarTemaEscuro:
        await _salvarTemaEscuro(false);
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Tema claro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.ativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: true));
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Parada por silêncio ativada.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: false));
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Parada por silêncio desativada.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.definirTempoSilencio:
        final segundos = int.tryParse(resultado.parametro ?? '');
        if (segundos == null) {
          _atualizarStatus('Diga o tempo de silêncio entre 3 e 12 segundos.');
          return VoiceCommandPageResult.handled();
        }
        await _salvar(
          configuracao.copyWith(
            paradaSilencio: true,
            tempoSilencioSegundos: segundos.clamp(3, 12).toInt(),
          ),
        );
        if (!mounted) {
          return VoiceCommandPageResult.handled(restartListening: false);
        }

        _atualizarStatus('Tempo de silêncio definido para $segundos segundos.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.scrollBaixo:
      case VoiceCommandType.scrollCima:
      case VoiceCommandType.scrollTopo:
      case VoiceCommandType.scrollFim:
        return await VoiceScrollHandler(
              controller: _voiceScrollController,
            ).handle(resultado) ??
            VoiceCommandPageResult.unavailable(
              recognized: resultado.recognized,
            );
      case VoiceCommandType.voltar:
        await suspendContextualVoiceListening();
        if (mounted) {
          Navigator.maybePop(context);
        }
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.buscarGravacoes:
      case VoiceCommandType.buscarProjetos:
      case VoiceCommandType.limparBusca:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.excluirProjeto:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.abrirAssistente:
        unawaited(openContextualVoiceHelp(VoiceCommandHelpContext.settings));
        return VoiceCommandPageResult.handled(
          message: 'Aqui estão os comandos disponíveis.',
        );
      case VoiceCommandType.criarComandoPersonalizado:
        if (widget.usuario == null) {
          _atualizarStatus(
            'Entre na sua conta para criar comandos personalizados.',
          );
          return VoiceCommandPageResult.handled();
        }
        final extracted = _extrairComandoPersonalizado(
          resultado.normalizedText.trim(),
        );
        _irParaFormularioComandoPersonalizado(
          frase: extracted.frase,
          tipoComando: extracted.tipoComando,
        );
        _atualizarStatus(
          extracted.frase.isNotEmpty
              ? 'Formulário preenchido. Confirme para salvar o comando.'
              : 'Role até o formulário e preencha a frase e a ação desejada.',
        );
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.confirmarAcao:
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.comecarExperiencia:
      case VoiceCommandType.jaTenhoConta:
      case VoiceCommandType.permitirMicrofone:
      case VoiceCommandType.continuarFluxo:
      case VoiceCommandType.entrarConta:
      case VoiceCommandType.ativarComandoPersonalizado:
      case VoiceCommandType.desativarComandoPersonalizado:
      case VoiceCommandType.excluirComandoPersonalizado:
        return VoiceCommandPageResult.unavailable(
          recognized: resultado.recognized,
        );
      case VoiceCommandType.sair:
        final confirmed = await showVoiceConfirmationDialog(
          id: 'logout',
          title: 'Sair da conta?',
          message: 'Você será desconectado do Touchless.',
          confirmLabel: 'Sair',
          cancelLabel: 'Cancelar',
          destructive: true,
        );
        if (confirmed) {
          unawaited(_sairDaContaLogout());
          return VoiceCommandPageResult.handled(restartListening: false);
        }
        return VoiceCommandPageResult.handled(message: 'Sair cancelado.');
      case VoiceCommandType.desconhecido:
        return VoiceCommandPageResult.unavailable(
          recognized: resultado.recognized,
        );
    }
  }

  Future<VoiceCommandPageResult> _handleIrParaHome(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleVoltarGlobal(CommandResult _) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetosGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => MeusProjetosPage(usuario: usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjetoGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(
        builder: (_) =>
            MeusProjetosPage(usuario: usuario, abrirCriacaoAoEntrar: true),
      ),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirGravacoesGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => MinhasGravacoesPage(usuario: usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboardGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirHistoricoGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: usuario)),
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirEditorGlobal(
    CommandResult _,
  ) async {
    final usuario = widget.usuario;
    if (usuario == null) {
      return VoiceCommandPageResult.handled(
        message: 'Usuario sem sessao autenticada.',
      );
    }

    return _navegarGlobal(
      MaterialPageRoute(builder: (_) => EditorPage(usuario: usuario)),
    );
  }

  Future<VoiceCommandPageResult> _navegarGlobal<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      await Navigator.push(context, route);
    }
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  void _atualizarStatus(String status) {
    voiceSetState(() {
      voiceStatusMessage = status;
    });
  }

  Widget _buildContaSection(BuildContext context, Usuario usuario) {
    final initial = (usuario.nome.isNotEmpty ? usuario.nome[0] : '?')
        .toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conta', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF6B3FA0),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    usuario.nome,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    usuario.email,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_aguardandoConfirmacaoLogout)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Diga "confirmar sair" para confirmar, ou "cancelar sair" para cancelar.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('logout_button'),
          onPressed: _fazendoLogout ? null : _handleLogoutButton,
          icon: _fazendoLogout
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout, size: 18),
          label: const Text('Sair da conta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade400,
            side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _frasePersonalizadaController.dispose();
    _voiceScrollController.dispose();
    _settingsController.removeListener(_onSettingsStateChanged);
    _settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = _settingsState;
    final configuracao = settingsState.configuration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        actions: [
          IconButton(
            key: const Key('settings_voice_command_help_button'),
            tooltip: 'Comandos desta tela',
            onPressed: _abrirAjudaComandosConfiguracoes,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: voiceOuvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: toggleContextualVoiceListening,
            icon: Icon(voiceOuvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: settingsState.loading || configuracao == null
          ? const AppLoadingView(message: 'Carregando configurações...')
          : ListView(
              controller: _voiceScrollController,
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                // ── Conta ──────────────────────────────────────────────────
                if (widget.usuario != null) ...[
                  _buildContaSection(context, widget.usuario!),
                  const SizedBox(height: AppSpacing.xl),
                ],
                Text(
                  'Aparência',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: configuracao.temaEscuro,
                  title: const Text('Tema escuro'),
                  subtitle: const Text(
                    'Alterna a interface entre tema claro e escuro.',
                  ),
                  onChanged: _salvarTemaEscuro,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Comandos de voz',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: configuracao.comandosVozAtivos,
                  title: const Text('Controle por voz'),
                  subtitle: const Text(
                    'Permite controlar gravações, reprodução e navegação por comandos.',
                  ),
                  onChanged: _alterandoControleVoz ? null : _alterarControleVoz,
                  secondary: _alterandoControleVoz
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                if (!configuracao.comandosVozAtivos) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _voicePermissionService.guidanceMessage(
                              _ultimoResultadoPermissao ??
                                  VoicePermissionResult.denied,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: _alterandoControleVoz
                                ? null
                                : () => _alterarControleVoz(true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar ativar novamente'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _voicePermissionService.openSystemSettings,
                    icon: const Icon(Icons.settings_applications_outlined),
                    label: const Text('Abrir permissões do Android'),
                  ),
                ],
                SwitchListTile(
                  value: configuracao.escutaContinua,
                  title: const Text('Escuta contínua'),
                  subtitle: const Text(
                    'Mantém o assistente ouvindo comandos sem tocar no microfone.',
                  ),
                  onChanged: configuracao.comandosVozAtivos
                      ? (value) => _salvar(
                          configuracao.copyWith(escutaContinua: value),
                        )
                      : null,
                ),
                SwitchListTile(
                  value: configuracao.feedbackSonoro,
                  title: const Text('Feedback sonoro'),
                  subtitle: const Text(
                    'Reserva a configuração para respostas auditivas do assistente.',
                  ),
                  onChanged: (value) =>
                      _salvar(configuracao.copyWith(feedbackSonoro: value)),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  key: _customCommandFormKey2,
                  'Comandos personalizados',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Form(
                  key: _customCommandFormKey,
                  child: TextFormField(
                    controller: _frasePersonalizadaController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Frase personalizada',
                      hintText: 'Ex.: modo palco',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateCommandPhrase,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _tipoComandoPersonalizado,
                  decoration: const InputDecoration(
                    labelText: 'Ação executada',
                    border: OutlineInputBorder(),
                  ),
                  items: CustomCommandCatalog.actions
                      .map(
                        (action) => DropdownMenuItem(
                          value: action.tipoComando,
                          child: Text(action.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _tipoComandoPersonalizado = value;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: _salvandoComandoPersonalizado
                      ? null
                      : _salvarComandoPersonalizado,
                  icon: _salvandoComandoPersonalizado
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Salvar comando'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (settingsState.customCommands.isEmpty)
                  Text(
                    'Você ainda não criou comandos personalizados. Salve uma frase para usá-la por voz.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...settingsState.customCommands.map((comando) {
                    final acao = CustomCommandCatalog.findByTipo(
                      comando.tipoComando,
                    );
                    final alternando =
                        _alternandoComandoPersonalizadoId == comando.id;
                    final excluindo =
                        _excluindoComandoPersonalizadoId == comando.id;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(comando.frase),
                      subtitle: Text(acao?.label ?? 'Ação personalizada'),
                      leading: Switch(
                        value: comando.ativo,
                        onChanged: alternando || excluindo
                            ? null
                            : (value) =>
                                  _alternarComandoPersonalizado(comando, value),
                      ),
                      trailing: IconButton(
                        tooltip: 'Excluir comando',
                        onPressed: alternando || excluindo
                            ? null
                            : () => _excluirComandoPersonalizado(comando),
                        icon: excluindo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline),
                      ),
                    );
                  }),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Gravação',
                  key: _silenceSectionKey,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: configuracao.paradaSilencio,
                  title: const Text('Parada automática por silêncio'),
                  subtitle: const Text(
                    'Encerra a gravação quando o app detectar silêncio por tempo suficiente.',
                  ),
                  onChanged: (value) =>
                      _salvar(configuracao.copyWith(paradaSilencio: value)),
                ),
                ListTile(
                  title: const Text('Tempo de silêncio'),
                  subtitle: Slider(
                    value:
                        (_tempoSilencioVisual ??
                                configuracao.tempoSilencioSegundos)
                            .toDouble(),
                    min: 3,
                    max: 12,
                    divisions: 9,
                    label:
                        '${_tempoSilencioVisual ?? configuracao.tempoSilencioSegundos}s',
                    onChanged: configuracao.paradaSilencio
                        ? (value) {
                            voiceSetState(() {
                              _tempoSilencioVisual = value.round();
                            });
                          }
                        : null,
                    onChangeEnd: configuracao.paradaSilencio
                        ? (value) => _salvarTempoSilencio(configuracao, value)
                        : null,
                  ),
                  trailing: Text(
                    '${_tempoSilencioVisual ?? configuracao.tempoSilencioSegundos}s',
                  ),
                ),
                ListTile(
                  title: const Text('Sensibilidade de silêncio'),
                  subtitle: Slider(
                    value: (_limiarSilencioVisual ??
                            configuracao.limiarSilencioDb)
                        .clamp(
                      ConfiguracaoApp.limiarSilencioDbMin,
                      ConfiguracaoApp.limiarSilencioDbMax,
                    ),
                    min: ConfiguracaoApp.limiarSilencioDbMin,
                    max: ConfiguracaoApp.limiarSilencioDbMax,
                    divisions: 50,
                    label:
                        '${(_limiarSilencioVisual ?? configuracao.limiarSilencioDb).toStringAsFixed(0)} dB',
                    onChanged: configuracao.paradaSilencio
                        ? (value) {
                            voiceSetState(() {
                              _limiarSilencioVisual = value;
                            });
                          }
                        : null,
                    onChangeEnd: configuracao.paradaSilencio
                        ? (value) =>
                              _salvarLimiarSilencio(configuracao, value)
                        : null,
                  ),
                  trailing: Text(
                    '${(_limiarSilencioVisual ?? configuracao.limiarSilencioDb).toStringAsFixed(0)} dB',
                  ),
                ),
              ],
            ),
      bottomNavigationBar: voiceStatusMessage == null
          ? null
          : VoiceStatusBar(
              message: voiceStatusMessage!,
              listening: voiceOuvindo,
              thinking: voiceIaPensando,
            ),
    );
  }
}
