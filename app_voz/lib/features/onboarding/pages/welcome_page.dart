import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_logo.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/configuracao_app.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/coordination/contextual_voice_listening_mixin.dart';
import '../../voices/coordination/voice_command_dispatcher.dart';
import '../../voices/coordination/voice_page_owners.dart';
import '../../voices/pages/cadastro_page.dart';
import '../../voices/pages/login_page.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/voice_permission_service.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    this.loginBuilder,
    this.cadastroBuilder,
    this.voicePermissionService,
    this.buscarConfiguracao,
  });

  final WidgetBuilder? loginBuilder;
  final WidgetBuilder? cadastroBuilder;
  final VoicePermissionService? voicePermissionService;
  final Future<ConfiguracaoApp> Function()? buscarConfiguracao;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with ContextualVoiceListeningMixin<WelcomePage> {
  String? _feedbackMicrofone;

  VoicePermissionService get _voicePermissionService =>
      widget.voicePermissionService ?? const VoicePermissionService();

  @override
  String get voiceOwnerId => VoicePageOwners.welcome;

  @override
  int? get voiceUsuarioId => null;

  @override
  String get voiceListeningPrompt => 'Ouvindo...';

  @override
  bool get voiceHandlesGlobalCommands => false;

  @override
  bool get voiceHandlesGlobalNavigationCommands => false;

  @override
  bool get voiceRegistersCommands => false;

  @override
  bool shouldUseAiForVoiceInput(String normalizedText) => false;

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher;

  @override
  void initState() {
    super.initState();
    voiceStatusMessage = 'Diga "começar" ou toque no botão.';
    voiceCommandDispatcher = VoiceCommandDispatcher(
      handlers: {
        VoiceCommandType.comecarExperiencia: _handleComecarVoz,
        VoiceCommandType.continuarFluxo: _handleComecarVoz,
        VoiceCommandType.jaTenhoConta: _handleJaTenhoContaVoz,
        VoiceCommandType.entrarConta: _handleJaTenhoContaVoz,
        VoiceCommandType.permitirMicrofone: _handlePermitirMicrofoneVoz,
        VoiceCommandType.cancelarAcao: (_) async =>
            VoiceCommandPageResult.handled(message: 'Tudo bem.'),
        VoiceCommandType.voltar: (_) async => VoiceCommandPageResult.handled(
          message: 'Você está na tela inicial.',
        ),
      },
    );
    unawaited(_carregarEscutaInicial());
  }

  Future<void> _carregarEscutaInicial() async {
    try {
      final buscarConfig =
          widget.buscarConfiguracao ??
          ConfiguracaoAppRepository.instance.buscarConfiguracao;
      final configuracao = await buscarConfig();
      if (!mounted) return;
      syncVoiceConfigFlags(configuracao);
      if (voiceEscutaContinuaAtiva) {
        scheduleVoiceListeningOnFirstFrame();
      }
    } catch (_) {
      // Configuração indisponível — microfone ativado manualmente pelo usuário.
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    super.dispose();
  }

  Future<void> _irParaCadastro() async {
    await suspendContextualVoiceListening();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: widget.cadastroBuilder ?? (_) => const CadastroPage(),
      ),
    );
  }

  Future<void> _irParaLogin() async {
    await suspendContextualVoiceListening();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: widget.loginBuilder ?? (_) => const LoginPage(),
      ),
    );
  }

  Future<void> _handlePermitirMicrofone() async {
    final resultado = await _voicePermissionService.requestMicrophone();
    if (!mounted) return;
    voiceSetState(() {
      _feedbackMicrofone = _voicePermissionService.guidanceMessage(resultado);
    });
    if (_voicePermissionService.shouldOpenSystemSettings(resultado)) {
      await _voicePermissionService.openSystemSettings();
    }
  }

  Future<VoiceCommandPageResult> _handleComecarVoz(CommandResult _) async {
    await _irParaCadastro();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handleJaTenhoContaVoz(
    CommandResult _,
  ) async {
    await _irParaLogin();
    return VoiceCommandPageResult.handled(restartListening: false);
  }

  Future<VoiceCommandPageResult> _handlePermitirMicrofoneVoz(
    CommandResult _,
  ) async {
    await _handlePermitirMicrofone();
    return VoiceCommandPageResult.handled(
      message:
          _feedbackMicrofone ?? 'Solicitando permissão de microfone...',
      restartListening: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: AppSpacing.xxl),

                      const AppLogo(height: 100),

                      const SizedBox(height: AppSpacing.xl),

                      Text(
                        'Touchless',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xs),

                      Text(
                        'Controle seus projetos musicais por voz.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      Text(
                        'Crie projetos, grave ideias e acesse suas gravações '
                        'sem tirar as mãos do instrumento.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      _FeatureCard(
                        icon: Icons.mic_rounded,
                        title: 'Comandos por voz',
                        description:
                            'Use comandos como "abrir projetos", "gravar" e '
                            '"minhas gravações".',
                        backgroundColor: colorScheme.primaryContainer,
                        iconColor: colorScheme.onPrimaryContainer,
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      _FeatureCard(
                        icon: Icons.folder_open_rounded,
                        title: 'Organização musical',
                        description:
                            'Separe ideias, gravações e projetos em um só lugar.',
                        backgroundColor: colorScheme.secondaryContainer,
                        iconColor: colorScheme.onSecondaryContainer,
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      _FeatureCard(
                        icon: Icons.music_note_rounded,
                        title: 'Feito para tocar',
                        description:
                            'Ideal para usar com o celular no suporte enquanto '
                            'você toca.',
                        backgroundColor: colorScheme.tertiaryContainer,
                        iconColor: colorScheme.onTertiaryContainer,
                      ),

                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Botões fixos — sempre visíveis, independente do scroll.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  key: const Key('welcome_comecar_button'),
                  onPressed: _irParaCadastro,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: const Text('Começar'),
                ),

                const SizedBox(height: AppSpacing.sm),

                OutlinedButton(
                  key: const Key('welcome_ja_tenho_conta_button'),
                  onPressed: _irParaLogin,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  child: const Text('Já tenho conta'),
                ),

                const SizedBox(height: AppSpacing.xs),

                TextButton(
                  key: const Key('welcome_permitir_microfone_button'),
                  onPressed: _handlePermitirMicrofone,
                  child: const Text('Permitir microfone'),
                ),

                if (_feedbackMicrofone != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                    ),
                    child: Text(
                      _feedbackMicrofone!,
                      key: const Key('welcome_microfone_feedback'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.secondary,
                      ),
                    ),
                  ),

                const SizedBox(height: AppSpacing.xs),
              ],
            ),
          ),

          VoiceStatusBar(
            message: voiceStatusMessage ?? '',
            listening: voiceOuvindo,
            thinking: voiceIaPensando,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: backgroundColor.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
