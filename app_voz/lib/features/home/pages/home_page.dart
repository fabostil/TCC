import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/ui/app_feedback.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../dashboard/pages/dashboard_page.dart';
import '../../history/pages/historico_page.dart';
import '../../projects/pages/meus_projetos_page.dart';
import '../../recordings/pages/minhas_gravacoes_page.dart';
import '../../settings/pages/configuracoes_page.dart';
import '../../voices/pages/login_page.dart';
import '../../voices/pages/voice_page.dart';
import '../../voices/services/ai_command_service.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/speech_service.dart';

class HomePage extends StatefulWidget {
  final Usuario usuario;

  const HomePage({super.key, required this.usuario});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SpeechService _speechService = SpeechService();
  final CommandService _commandService = const CommandService();
  final AiCommandService _aiCommandService = AiCommandService();

  ConfiguracaoApp? _configuracao;
  bool _verificandoPrimeiraExecucao = true;
  bool _ouvindo = false;
  bool _iaPensando = false;
  bool _escutaInicialSolicitada = false;
  String _statusVoz = 'Assistente de voz aguardando.';

  @override
  void initState() {
    super.initState();
    _carregarConfiguracaoInicial();
  }

  Future<void> _carregarConfiguracaoInicial() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
      _verificandoPrimeiraExecucao = false;
    });

    if (!configuracao.primeiraExecucaoConcluida) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mostrarConfiguracaoInicialVoz();
        }
      });
    } else if (configuracao.comandosVozAtivos) {
      _agendarEscutaInicial();
    }
  }

  Future<void> _mostrarConfiguracaoInicialVoz() async {
    final habilitarVoz = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Habilitar comandos de voz?'),
        content: const Text(
          'Com essa opção ativa, você poderá controlar gravações, reprodução e navegação por comandos de voz. Você ainda poderá usar os botões normalmente e alterar isso depois em Configurações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Usar modo manual'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Habilitar voz'),
          ),
        ],
      ),
    );

    final deveHabilitar = habilitarVoz ?? false;
    var comandosAtivos = deveHabilitar;

    if (deveHabilitar) {
      final permissao = await Permission.microphone.request();
      comandosAtivos = permissao.isGranted;

      if (!permissao.isGranted && mounted) {
        AppFeedback.showMessage(
          context,
          'Permissão de microfone negada. O app continuará em modo manual.',
        );
      }
    }

    await ConfiguracaoAppRepository.instance.concluirPrimeiraExecucao(
      comandosVozAtivos: comandosAtivos,
    );

    final atualizada = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = atualizada;
    });

    if (atualizada.comandosVozAtivos) {
      _agendarEscutaInicial();
    }
  }

  void _agendarEscutaInicial() {
    if (_escutaInicialSolicitada) {
      return;
    }

    _escutaInicialSolicitada = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _iniciarEscutaHome();
      }
    });
  }

  void _sair(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _abrirNovoProjeto(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );
  }

  void _abrirProjetos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );
  }

  void _abrirAssistente(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoicePage(usuario: widget.usuario)),
    );
  }

  Future<void> _alternarEscutaHome() async {
    if (_ouvindo) {
      await _speechService.stopListening();

      if (!mounted) {
        return;
      }

      setState(() {
        _ouvindo = false;
        _statusVoz = 'Escuta encerrada.';
      });
      return;
    }

    await _iniciarEscutaHome();
  }

  Future<void> _iniciarEscutaHome() async {
    final configuracao =
        _configuracao ??
        await ConfiguracaoAppRepository.instance.buscarConfiguracao();

    if (!mounted) {
      return;
    }

    if (!configuracao.comandosVozAtivos) {
      setState(() {
        _ouvindo = false;
        _statusVoz = 'Comandos de voz desativados.';
      });
      return;
    }

    setState(() {
      _ouvindo = true;
      _statusVoz = 'Ouvindo comando...';
    });

    await _speechService.startListening(
      onResult: (texto) {
        setState(() {
          _statusVoz = 'Comando detectado: $texto';
        });

        unawaited(_executarComandoHome(texto));
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }

        if (status == 'listening') {
          setState(() {
            _ouvindo = true;
            _statusVoz = 'Estou ouvindo...';
          });
        }

        if (status == 'done' || status == 'notListening') {
          setState(() {
            _ouvindo = false;
          });

          if (_configuracao?.escutaContinua == true) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_ouvindo) {
                _iniciarEscutaHome();
              }
            });
          }
        }
      },
      onError: (error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ouvindo = false;
          _statusVoz = error == 'error_speech_timeout'
              ? 'Nenhuma fala detectada.'
              : 'Erro no reconhecimento de voz: $error';
        });
      },
    );
  }

  void _abrirGravacoes(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );
  }

  void _abrirDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );
  }

  void _abrirHistorico(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );
  }

  Future<void> _executarComandoHome(String comando) async {
    var resultado = _commandService.interpret(comando);

    if (resultado.normalizedText.isEmpty) {
      return;
    }

    if (!resultado.recognized && _aiCommandService.isConfigured) {
      setState(() {
        _iaPensando = true;
        _statusVoz = 'IA pensando...';
      });

      resultado = await _aiCommandService.interpretUnknown(comando);

      if (!mounted) {
        return;
      }

      setState(() {
        _iaPensando = false;
      });
    }

    switch (resultado.type) {
      case VoiceCommandType.abrirDashboard:
        _abrirDashboard(context);
        return;
      case VoiceCommandType.abrirProjetos:
        _abrirProjetos(context);
        return;
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.listarGravacoes:
        _abrirGravacoes(context);
        return;
      case VoiceCommandType.abrirConfiguracoes:
        await _abrirConfiguracoes(context);
        return;
      case VoiceCommandType.abrirAssistente:
        _abrirAssistente(context);
        return;
      case VoiceCommandType.abrirHistorico:
        _abrirHistorico(context);
        return;
      case VoiceCommandType.voltar:
        Navigator.maybePop(context);
        return;
      case VoiceCommandType.sair:
        _sair(context);
        return;
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.desconhecido:
        setState(() {
          _iaPensando = false;
          _statusVoz = _aiCommandService.isConfigured
              ? 'Comando nao executavel nesta tela.'
              : 'Comando nao reconhecido. Configure GEMINI_API_KEY para NLU.';
        });
        return;
    }
  }

  Future<void> _abrirConfiguracoes(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
    );

    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
    });
  }

  @override
  void dispose() {
    _speechService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comandosAtivos = _configuracao?.comandosVozAtivos == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente Musical'),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            onPressed: () => _abrirConfiguracoes(context),
            icon: const Icon(Icons.settings_rounded),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () => _sair(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                    theme.colorScheme.primary.withOpacity(0.14),
                    theme.colorScheme.secondary.withOpacity(0.10),
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
                        _ouvindo ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: comandosAtivos
                            ? theme.colorScheme.primary
                            : theme.disabledColor,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _iaPensando ? 'IA pensando...' : _statusVoz,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: _ouvindo ? 'Parar escuta' : 'Ouvir comando',
                        onPressed: comandosAtivos ? _alternarEscutaHome : null,
                        icon: Icon(
                          _ouvindo
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none_rounded,
                        ),
                      ),
                    ],
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
              subtitle: 'Crie um projeto musical e vá direto para o editor.',
              onTap: () => _abrirNovoProjeto(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _HomeCard(
              icon: Icons.mic_none_rounded,
              title: 'Assistente de voz',
              subtitle: comandosAtivos
                  ? 'Use comandos para iniciar, pausar e encerrar gravações.'
                  : 'Comandos de voz desativados. Ative em Configurações.',
              onTap: () => _abrirAssistente(context),
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
              subtitle: 'Visualize métricas e resumos de uso do sistema.',
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
              onTap: () => _abrirConfiguracoes(context),
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
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
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
