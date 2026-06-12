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
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/custom_command_service.dart';
import '../../voices/services/voice_permission_service.dart';
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
    return 'Informe uma frase valida para o comando.';
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

  const ConfiguracoesPage({super.key, this.usuario});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage>
    with ContextualVoiceListeningMixin<ConfiguracoesPage> {
  final VoicePermissionService _voicePermissionService =
      const VoicePermissionService();
  final SettingsController _settingsController = SettingsController();
  final _customCommandFormKey = GlobalKey<FormState>();
  final TextEditingController _frasePersonalizadaController =
      TextEditingController();
  final ScrollController _voiceScrollController = ScrollController();
  VoicePermissionResult? _ultimoResultadoPermissao;
  String _tipoComandoPersonalizado =
      CustomCommandCatalog.actions.first.tipoComando;
  int? _tempoSilencioVisual;
  bool _salvandoComandoPersonalizado = false;
  bool _alterandoControleVoz = false;
  int? _alternandoComandoPersonalizadoId;
  int? _excluindoComandoPersonalizadoId;

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
    _settingsController.addListener(_onSettingsStateChanged);
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.settings,
      goHome: _handleIrParaHome,
      openProjects: _handleAbrirProjetosGlobal,
      openRecordings: _handleAbrirGravacoesGlobal,
      openDashboard: _handleAbrirDashboardGlobal,
      openHistory: _handleAbrirHistoricoGlobal,
      openNewProject: _handleAbrirNovoProjetoGlobal,
      goBack: _handleVoltarGlobal,
    );
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchSettingsVoice,
    );
    _carregarConfiguracao();
    scheduleVoiceListeningOnFirstFrame();
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
    await startContinuousVoiceListeningIfActive();
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
      _atualizarStatus('Comando personalizado salvo.');
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

      _atualizarStatus('Comando personalizado excluido.');
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

        _atualizarStatus('Controle por voz desativado.');
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
              : 'Permissão de microfone negada.',
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

  Future<VoiceCommandPageResult> _dispatchSettingsVoice(
    CommandResult resultado,
  ) async {
    final configuracao = _settingsState.configuration;
    if (configuracao == null) {
      return VoiceCommandPageResult.handled(
        message: 'Configuracao ainda carregando.',
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
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.confirmarAcao:
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.sair:
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
                    'Nenhum comando personalizado cadastrado.',
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
                      subtitle: Text(acao?.label ?? 'Acao personalizada'),
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
                Text('Gravação', style: Theme.of(context).textTheme.titleLarge),
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
