import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../editor/pages/editor_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_navigation_command_handler.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/coordination/voice_scroll_handler.dart';
import '../../voices/pages/login_page.dart';
import '../../voices/services/auth_session_service.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/voice_permission_service.dart';
import '../../voices/widgets/voice_command_help_dialog.dart';

typedef HomeLoginBuilder = Widget Function();
typedef HomeLogoutConfirmation = Future<bool> Function();

class HomePage extends StatefulWidget {
  final Usuario usuario;

  const HomePage({
    super.key,
    required this.usuario,
    this.authSessionService,
    this.voicePermissionService,
    this.buscarConfiguracao,
    this.concluirPrimeiraExecucao,
    this.loginBuilder,
    this.confirmarLogout,
  });

  final AuthSessionService? authSessionService;
  final VoicePermissionService? voicePermissionService;
  final Future<ConfiguracaoApp> Function()? buscarConfiguracao;
  final Future<void> Function({required bool comandosVozAtivos})?
  concluirPrimeiraExecucao;
  final HomeLoginBuilder? loginBuilder;
  final HomeLogoutConfirmation? confirmarLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with ContextualVoiceListeningMixin<HomePage> {
  final ScrollController _scrollController = ScrollController();
  ConfiguracaoApp? _configuracao;
  bool _verificandoPrimeiraExecucao = true;
  bool _escutaInicialSolicitada = false;
  DateTime? _ultimoComandoExecutadoEm;
  String? _ultimoComandoNormalizado;

  VoicePermissionService get _voicePermissionService =>
      widget.voicePermissionService ?? const VoicePermissionService();

  AuthSessionService get _authSessionService =>
      widget.authSessionService ?? AuthSessionService.instance;

  Future<ConfiguracaoApp> _buscarConfiguracao() {
    return widget.buscarConfiguracao?.call() ??
        ConfiguracaoAppRepository.instance.buscarConfiguracao();
  }

  Future<void> _concluirPrimeiraExecucao({required bool comandosVozAtivos}) {
    final concluirPrimeiraExecucao = widget.concluirPrimeiraExecucao;
    if (concluirPrimeiraExecucao != null) {
      return concluirPrimeiraExecucao(comandosVozAtivos: comandosVozAtivos);
    }

    return ConfiguracaoAppRepository.instance.concluirPrimeiraExecucao(
      comandosVozAtivos: comandosVozAtivos,
    );
  }

  @override
  String get voiceOwnerId => VoicePageOwners.home;

  @override
  int? get voiceUsuarioId => widget.usuario.id;

  @override
  String get voiceListeningPrompt => 'Ouvindo comando...';

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  late final VoiceNavigationCommandHandler voiceNavigationCommandHandler;

  @override
  void initState() {
    super.initState();
    voiceStatusMessage = 'Assistente de voz aguardando.';
    voiceNavigationCommandHandler = VoiceNavigationCommandHandler(
      currentDestination: VoiceNavigationDestination.home,
      openProjects: _handleAbrirProjetos,
      openRecordings: _handleAbrirGravacoes,
      openDashboard: _handleAbrirDashboard,
      openHistory: _handleAbrirHistorico,
      openSettings: _handleAbrirConfiguracoes,
      openEditor: _handleAbrirEditor,
      openNewProject: _handleAbrirNovoProjeto,
      goBack: _handleVoltar,
    );
    voiceCommandDispatcher = VoiceCommandDispatcher(
      handlers: {
        VoiceCommandType.abrirNovoProjeto: _handleAbrirNovoProjeto,
        VoiceCommandType.abrirDashboard: _handleAbrirDashboard,
        VoiceCommandType.abrirProjetos: _handleAbrirProjetos,
        VoiceCommandType.abrirGravacoes: _handleAbrirGravacoes,
        VoiceCommandType.listarGravacoes: _handleAbrirGravacoes,
        VoiceCommandType.abrirConfiguracoes: _handleAbrirConfiguracoes,
        VoiceCommandType.abrirAssistente: _handleAssistenteAtivo,
        VoiceCommandType.abrirHistorico: _handleAbrirHistorico,
        VoiceCommandType.abrirEditor: _handleAbrirEditor,
        VoiceCommandType.voltar: _handleVoltar,
        VoiceCommandType.scrollBaixo: _handleScrollPorVoz,
        VoiceCommandType.scrollCima: _handleScrollPorVoz,
        VoiceCommandType.scrollTopo: _handleScrollPorVoz,
        VoiceCommandType.scrollFim: _handleScrollPorVoz,
        VoiceCommandType.sair: _handleSair,
      },
      onFallback: _handleComandoIndisponivel,
    );
    _carregarConfiguracaoInicial();
  }

  @override
  void onVoiceConfigurationChanged(ConfiguracaoApp configuracao) {
    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
    });

    if (configuracao.comandosVozAtivos && configuracao.escutaContinua) {
      _agendarEscutaInicial();
    }
  }

  Future<void> _carregarConfiguracaoInicial() async {
    final configuracao = await _buscarConfiguracao();

    if (!mounted) {
      return;
    }

    syncVoiceConfigFlags(configuracao);
    setState(() {
      _configuracao = configuracao;
      _verificandoPrimeiraExecucao = false;
    });

    if (!configuracao.primeiraExecucaoConcluida) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_habilitarVozInicialAutomaticamente());
        }
      });
    } else if (configuracao.comandosVozAtivos) {
      _agendarEscutaInicial();
    }
  }

  Future<void> _habilitarVozInicialAutomaticamente() async {
    final permissao = await _voicePermissionService.requestMicrophone();
    final comandosAtivos = permissao == VoicePermissionResult.granted;

    await _concluirPrimeiraExecucao(comandosVozAtivos: comandosAtivos);

    final atualizada = await _buscarConfiguracao();

    if (!mounted) {
      return;
    }

    syncVoiceConfigFlags(atualizada);
    setState(() {
      _configuracao = atualizada;
      voiceStatusMessage = comandosAtivos
          ? 'Assistente ativado. Estou ouvindo comandos.'
          : 'Permita o uso do microfone para controlar o app por voz. Modo manual ativo.';
    });

    if (atualizada.comandosVozAtivos) {
      _agendarEscutaInicial();
      return;
    }

    await _orientarPermissaoNegada(permissao);
  }

  Future<void> _orientarPermissaoNegada(VoicePermissionResult permissao) async {
    final mensagem = _voicePermissionService.guidanceMessage(permissao);
    AppFeedback.showMessage(context, mensagem);

    final abrirConfiguracoesSistema = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microfone indisponivel'),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar manual'),
          ),
          if (_voicePermissionService.shouldOpenSystemSettings(permissao))
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.settings_applications_outlined),
              label: const Text('Abrir permissoes'),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, false);
                _abrirConfiguracoes();
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Ver configurações'),
            ),
        ],
      ),
    );

    if (abrirConfiguracoesSistema == true) {
      await _voicePermissionService.openSystemSettings();
    }
  }

  void _agendarEscutaInicial() {
    if (_escutaInicialSolicitada) {
      return;
    }

    _escutaInicialSolicitada = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _escutaInicialSolicitada = false;
      if (mounted) {
        unawaited(startContinuousVoiceListeningIfActive());
      }
    });
  }

  Future<void> _alternarEscutaHome() async {
    await toggleContextualVoiceListening();
  }

  Future<void> _sairDaConta() async {
    final confirmar =
        await widget.confirmarLogout?.call() ??
        await showVoiceConfirmationDialog(
          id: 'logout',
          title: 'Sair do app?',
          message: 'Deseja encerrar a sessao e voltar para o login?',
          confirmLabel: 'Sair',
        );

    if (confirmar != true || !mounted) {
      return;
    }

    try {
      await _authSessionService.logout();
    } on AuthSessionLogoutException {
      if (!mounted) {
        return;
      }
      AppFeedback.showMessage(
        context,
        'Não consegui sair da conta agora. Tente novamente.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => widget.loginBuilder?.call() ?? const LoginPage(),
      ),
      (route) => false,
    );
  }

  Future<VoiceCommandPageResult> _handleAbrirNovoProjeto(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirProjetos(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirGravacoes(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirDashboard(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirHistorico(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirConfiguracoes(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _abrirConfiguracoes();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAbrirEditor(
    CommandResult result,
  ) async {
    if (_ignorarComandoDuplicado(result)) {
      return VoiceCommandPageResult.handled(restartListening: false);
    }

    await _navegarERetomar(
      MaterialPageRoute(builder: (_) => EditorPage(usuario: widget.usuario)),
    );
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleAssistenteAtivo(CommandResult _) async {
    return VoiceCommandPageResult.handled(
      message: 'Assistente de voz já está ativo na tela inicial.',
    );
  }

  Future<VoiceCommandPageResult> _handleVoltar(CommandResult _) async {
    if (mounted) {
      Navigator.maybePop(context);
    }
    return VoiceCommandPageResult.handled();
  }

  Future<VoiceCommandPageResult> _handleSair(CommandResult _) async {
    await _sairDaConta();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleScrollPorVoz(
    CommandResult result,
  ) async {
    return await VoiceScrollHandler(
          controller: _scrollController,
        ).handle(result) ??
        VoiceCommandPageResult.unavailable(recognized: result.recognized);
  }

  Future<VoiceCommandPageResult> _handleComandoIndisponivel(
    CommandResult result,
  ) async {
    if (result.type == VoiceCommandType.definirDescricaoProjeto ||
        result.type == VoiceCommandType.substituirDescricaoProjeto) {
      return VoiceCommandPageResult.handled(
        message: 'Esse comando so esta disponivel ao editar um projeto.',
      );
    }

    return VoiceCommandPageResult.handled(
      message: result.recognized
          ? 'Comando não executável nesta tela.'
          : unknownVoiceCommandMessage,
    );
  }

  bool _ignorarComandoDuplicado(CommandResult result) {
    final agora = DateTime.now();
    final ultimoComandoEm = _ultimoComandoExecutadoEm;
    final comandoRepetido =
        _ultimoComandoNormalizado == result.normalizedText &&
        ultimoComandoEm != null &&
        agora.difference(ultimoComandoEm).inSeconds < 3;

    if (comandoRepetido) {
      return true;
    }

    _ultimoComandoNormalizado = result.normalizedText;
    _ultimoComandoExecutadoEm = agora;
    return false;
  }

  Future<void> _navegarERetomar<T>(Route<T> route) async {
    await suspendContextualVoiceListening();
    if (mounted) {
      await Navigator.push(context, route);
    }
    await _retomarEscutaAposNavegacao();
  }

  Future<void> _abrirNovoProjeto(BuildContext context) async {
    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  Future<void> _abrirProjetos(BuildContext context) async {
    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  Future<void> _abrirGravacoes(BuildContext context) async {
    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<void> _abrirDashboard(BuildContext context) async {
    await _navegarERetomar(
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
  }

  Future<void> _abrirHistorico(BuildContext context) async {
    await _navegarERetomar(
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
  }

  Future<void> _abrirConfiguracoes() async {
    await _navegarERetomar(
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );
  }

  Future<void> _abrirAjudaComandosVoz() {
    return showVoiceCommandHelpDialog(
      context,
      contextType: VoiceCommandHelpContext.home,
    );
  }

  Future<void> _retomarEscutaAposNavegacao() async {
    final configuracao = await _buscarConfiguracao();

    if (!mounted) {
      return;
    }

    syncVoiceConfigFlags(configuracao);
    setState(() {
      _configuracao = configuracao;
    });

    if (voiceEscutaContinuaAtiva) {
      await startContinuousVoiceListeningIfActive();
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comandosAtivos = _configuracao?.comandosVozAtivos == true;
    final statusVoz = voiceStatusMessage ?? 'Assistente de voz aguardando.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Touchless'),
        actions: [
          IconButton(
            key: const Key('home_settings_button'),
            tooltip: 'Configurações',
            onPressed: _abrirConfiguracoes,
            icon: const Icon(Icons.settings_rounded),
          ),
          IconButton(
            key: const Key('home_logout_button'),
            tooltip: 'Sair',
            onPressed: _sairDaConta,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.14),
                    theme.colorScheme.secondary.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá, ${widget.usuario.nome}',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    comandosAtivos
                        ? 'Comandos de voz ativos. Você ainda pode usar os botões sempre que quiser.'
                        : 'Modo manual ativo. Você pode habilitar comandos de voz em Configurações.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Icon(
                        voiceOuvindo
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: comandosAtivos
                            ? theme.colorScheme.primary
                            : theme.disabledColor,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          voiceIaPensando ? 'IA pensando...' : statusVoz,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: voiceOuvindo
                            ? 'Parar escuta'
                            : 'Ouvir comando',
                        onPressed: comandosAtivos ? _alternarEscutaHome : null,
                        icon: Icon(
                          voiceOuvindo
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Tooltip(
                    message: 'Ver comandos de voz',
                    child: OutlinedButton.icon(
                      key: const Key('home_voice_command_help_button'),
                      onPressed: _abrirAjudaComandosVoz,
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Ver comandos de voz'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            if (_verificandoPrimeiraExecucao)
              const LinearProgressIndicator(minHeight: 2),
            if (_verificandoPrimeiraExecucao)
              const SizedBox(height: AppSpacing.md),
            Text('Atalhos', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.add_circle_outline_rounded,
              title: 'Novo projeto',
              subtitle: 'Crie um projeto musical e va direto para o editor.',
              onTap: () => _abrirNovoProjeto(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.folder_outlined,
              title: 'Meus projetos',
              subtitle: 'Acompanhe os projetos criados e seus detalhes.',
              onTap: () => _abrirProjetos(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.library_music_outlined,
              title: 'Minhas gravações',
              subtitle: 'Reproduza, renomeie e exclua gravações salvas.',
              onTap: () => _abrirGravacoes(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.insights_outlined,
              title: 'Dashboard',
              subtitle: 'Visualize metricas e resumos de uso do sistema.',
              onTap: () => _abrirDashboard(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.history_rounded,
              title: 'Histórico',
              subtitle: 'Consulte comandos, gravações e ações registradas.',
              onTap: () => _abrirHistorico(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.settings_outlined,
              title: 'Configurações',
              subtitle: 'Ajuste comandos de voz, escuta e opções de gravação.',
              onTap: _abrirConfiguracoes,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
