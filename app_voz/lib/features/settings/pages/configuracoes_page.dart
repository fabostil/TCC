import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../models/comando_personalizado.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_personalizado_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/custom_command_service.dart';
import '../../voices/services/voice_permission_service.dart';

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
  final TextEditingController _frasePersonalizadaController =
      TextEditingController();
  bool _carregando = true;
  ConfiguracaoApp? _configuracao;
  List<ComandoPersonalizado> _comandosPersonalizados = [];
  String _tipoComandoPersonalizado =
      CustomCommandCatalog.actions.first.tipoComando;

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
  void initState() {
    super.initState();
    voiceCommandDispatcher = VoiceCommandDispatcher(
      onFallback: _dispatchSettingsVoice,
    );
    _carregarConfiguracao();
    scheduleVoiceListeningOnFirstFrame();
  }

  Future<void> _carregarConfiguracao() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();
    final comandosPersonalizados = await _listarComandosPersonalizados();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
      _comandosPersonalizados = comandosPersonalizados;
      _carregando = false;
    });

    syncVoiceConfigFlags(configuracao);
    await startContinuousVoiceListeningIfActive();
  }

  Future<void> _salvar(ConfiguracaoApp configuracao) async {
    setState(() {
      _configuracao = configuracao;
    });

    await ConfiguracaoAppRepository.instance.salvarConfiguracao(configuracao);
  }

  Future<List<ComandoPersonalizado>> _listarComandosPersonalizados() async {
    final usuarioId = widget.usuario?.id;
    if (usuarioId == null) {
      return [];
    }

    return ComandoPersonalizadoRepository.instance.listarPorUsuario(usuarioId);
  }

  Future<void> _recarregarComandosPersonalizados() async {
    final comandos = await _listarComandosPersonalizados();

    if (!mounted) {
      return;
    }

    setState(() {
      _comandosPersonalizados = comandos;
    });
  }

  Future<void> _salvarComandoPersonalizado() async {
    final usuarioId = widget.usuario?.id;
    final frase = _frasePersonalizadaController.text.trim();

    if (usuarioId == null) {
      _atualizarStatus('Entre novamente para criar comandos personalizados.');
      return;
    }

    if (frase.length < 3) {
      _atualizarStatus('Informe uma frase com pelo menos 3 caracteres.');
      return;
    }

    final acao = CustomCommandCatalog.findByTipo(_tipoComandoPersonalizado);
    if (acao == null) {
      _atualizarStatus('Selecione uma ação válida.');
      return;
    }

    await ComandoPersonalizadoRepository.instance.salvar(
      ComandoPersonalizado(
        usuarioId: usuarioId,
        frase: frase,
        tipoComando: acao.tipoComando,
        ativo: true,
        dataCriacao: DateTime.now().toIso8601String(),
      ),
    );

    _frasePersonalizadaController.clear();
    await _recarregarComandosPersonalizados();
    _atualizarStatus('Comando personalizado salvo.');
  }

  Future<void> _alternarComandoPersonalizado(
    ComandoPersonalizado comando,
    bool ativo,
  ) async {
    final id = comando.id;
    if (id == null) {
      return;
    }

    await ComandoPersonalizadoRepository.instance.alternarAtivo(
      id: id,
      ativo: ativo,
    );
    await _recarregarComandosPersonalizados();
  }

  Future<void> _excluirComandoPersonalizado(
    ComandoPersonalizado comando,
  ) async {
    final id = comando.id;
    if (id == null) {
      return;
    }

    await ComandoPersonalizadoRepository.instance.excluir(id);
    await _recarregarComandosPersonalizados();
    _atualizarStatus('Comando personalizado excluído.');
  }

  Future<void> _salvarTemaEscuro(bool ativo) async {
    final configuracao = _configuracao;
    if (configuracao == null) {
      return;
    }

    await _salvar(configuracao.copyWith(temaEscuro: ativo));
    await AppThemeController.instance.definirTemaEscuro(ativo);
  }

  Future<void> _alterarControleVoz(bool ativo) async {
    final configuracao = _configuracao;
    if (configuracao == null) {
      return;
    }

    if (!ativo) {
      await _salvar(
        configuracao.copyWith(comandosVozAtivos: false, escutaContinua: false),
      );
      await suspendContextualVoiceListening(keepManualPause: true);
      _atualizarStatus('Controle por voz desativado.');
      return;
    }

    final permissao = await _voicePermissionService.requestMicrophone();
    if (permissao != VoicePermissionResult.granted) {
      await _salvar(
        configuracao.copyWith(comandosVozAtivos: false, escutaContinua: false),
      );
      _atualizarStatus(
        permissao == VoicePermissionResult.permanentlyDenied
            ? 'Microfone bloqueado nas configurações do Android.'
            : 'Permissão de microfone negada.',
      );
      return;
    }

    await _salvar(
      configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
    );
    syncVoiceConfigFlags(
      configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
    );
    voiceParadaManual = false;
    _atualizarStatus('Controle por voz ativado.');
    scheduleVoiceContinuousRestart();
  }

  Future<VoiceCommandPageResult> _dispatchSettingsVoice(
    CommandResult resultado,
  ) async {
    final configuracao = _configuracao;
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
        syncVoiceConfigFlags(
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
        );
        _atualizarStatus('Escuta contínua ativada.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarEscutaContinua:
        await _salvar(configuracao.copyWith(escutaContinua: false));
        syncVoiceConfigFlags(configuracao.copyWith(escutaContinua: false));
        _atualizarStatus('Escuta contínua desativada.');
        return VoiceCommandPageResult.handled(restartListening: false);
      case VoiceCommandType.ativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: true));
        _atualizarStatus('Feedback sonoro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: false));
        _atualizarStatus('Feedback sonoro desativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.ativarTemaEscuro:
        await _salvarTemaEscuro(true);
        _atualizarStatus('Tema escuro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarTemaEscuro:
        await _salvarTemaEscuro(false);
        _atualizarStatus('Tema claro ativado.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.ativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: true));
        _atualizarStatus('Parada por silêncio ativada.');
        return VoiceCommandPageResult.handled();
      case VoiceCommandType.desativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: false));
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
        _atualizarStatus('Tempo de silêncio definido para $segundos segundos.');
        return VoiceCommandPageResult.handled();
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
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.renomearProjeto:
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

  void _atualizarStatus(String status) {
    voiceSetState(() {
      voiceStatusMessage = status;
    });
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _frasePersonalizadaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuracao = _configuracao;

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
      body: _carregando || configuracao == null
          ? const AppLoadingView(message: 'Carregando configurações...')
          : ListView(
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
                  onChanged: _alterarControleVoz,
                ),
                if (!configuracao.comandosVozAtivos) ...[
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
                TextField(
                  controller: _frasePersonalizadaController,
                  decoration: const InputDecoration(
                    labelText: 'Frase personalizada',
                    hintText: 'Ex.: modo palco',
                    border: OutlineInputBorder(),
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
                  onPressed: _salvarComandoPersonalizado,
                  icon: const Icon(Icons.add),
                  label: const Text('Salvar comando'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_comandosPersonalizados.isEmpty)
                  Text(
                    'Nenhum comando personalizado cadastrado.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ..._comandosPersonalizados.map((comando) {
                    final acao = CustomCommandCatalog.findByTipo(
                      comando.tipoComando,
                    );

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(comando.frase),
                      subtitle: Text(acao?.label ?? comando.tipoComando),
                      leading: Switch(
                        value: comando.ativo,
                        onChanged: (value) =>
                            _alternarComandoPersonalizado(comando, value),
                      ),
                      trailing: IconButton(
                        tooltip: 'Excluir comando',
                        onPressed: () => _excluirComandoPersonalizado(comando),
                        icon: const Icon(Icons.delete_outline),
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
                    value: configuracao.tempoSilencioSegundos.toDouble(),
                    min: 3,
                    max: 12,
                    divisions: 9,
                    label: '${configuracao.tempoSilencioSegundos}s',
                    onChanged: configuracao.paradaSilencio
                        ? (value) => setState(() {
                            _configuracao = configuracao.copyWith(
                              tempoSilencioSegundos: value.round(),
                            );
                          })
                        : null,
                    onChangeEnd: configuracao.paradaSilencio
                        ? (value) => _salvar(
                            configuracao.copyWith(
                              tempoSilencioSegundos: value.round(),
                            ),
                          )
                        : null,
                  ),
                  trailing: Text('${configuracao.tempoSilencioSegundos}s'),
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
