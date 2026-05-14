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
import '../../voices/controllers/voice_command_controller.dart';
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
  final VoiceCommandController _commandController = VoiceCommandController();

  ConfiguracaoApp? _configuracao;
  bool _verificandoPrimeiraExecucao = true;
  bool _ouvindo = false;
  bool _iaPensando = false;
  bool _escutaInicialSolicitada = false;
  bool _escutaContinuaSuspensa = false;
  bool _executandoComandoVoz = false;
  DateTime? _ultimoComandoExecutadoEm;
  String? _ultimoComandoNormalizado;
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

  Future<void> _sair(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do app?'),
        content: const Text('Deseja encerrar a sessao e voltar para o login?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmar != true || !context.mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _abrirNovoProjeto(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(
          usuario: widget.usuario,
          abrirCriacaoAoEntrar: true,
        ),
      ),
    );

    await _retomarEscutaAposNavegacao();
  }

  Future<void> _abrirProjetos(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeusProjetosPage(usuario: widget.usuario),
      ),
    );

    await _retomarEscutaAposNavegacao();
  }

  void _abrirAssistente(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoicePage(usuario: widget.usuario)),
    );
  }

  Future<void> _alternarEscutaHome() async {
    if (_ouvindo) {
      _escutaContinuaSuspensa = true;
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

    _escutaContinuaSuspensa = false;
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

          if (_configuracao?.escutaContinua == true &&
              !_escutaContinuaSuspensa &&
              !_executandoComandoVoz) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted &&
                  !_ouvindo &&
                  !_escutaContinuaSuspensa &&
                  !_executandoComandoVoz) {
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

  Future<void> _abrirGravacoes(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MinhasGravacoesPage(usuario: widget.usuario),
      ),
    );

    await _retomarEscutaAposNavegacao();
  }

  Future<void> _abrirDashboard(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(usuario: widget.usuario)),
    );

    await _retomarEscutaAposNavegacao();
  }

  Future<void> _abrirHistorico(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoricoPage(usuario: widget.usuario)),
    );

    await _retomarEscutaAposNavegacao();
  }

  Future<void> _executarComandoHome(String comando) async {
    if (_executandoComandoVoz) {
      return;
    }

    _executandoComandoVoz = true;

    final resultadoController = await _commandController.interpret(
      comando,
      onAiStarted: () {
        if (!mounted) {
          return;
        }

        setState(() {
          _iaPensando = true;
          _statusVoz = 'IA pensando...';
        });
      },
    );
    final resultado = resultadoController.commandResult;

    if (!mounted) {
      _executandoComandoVoz = false;
      return;
    }

    if (_iaPensando) {
      setState(() {
        _iaPensando = false;
      });
    }

    if (resultado.normalizedText.isEmpty) {
      _executandoComandoVoz = false;
      return;
    }

    final agora = DateTime.now();
    final ultimoComandoEm = _ultimoComandoExecutadoEm;
    final comandoRepetido =
        _ultimoComandoNormalizado == resultado.normalizedText &&
        ultimoComandoEm != null &&
        agora.difference(ultimoComandoEm).inSeconds < 3;

    if (comandoRepetido) {
      _executandoComandoVoz = false;
      return;
    }

    _ultimoComandoNormalizado = resultado.normalizedText;
    _ultimoComandoExecutadoEm = agora;

    switch (resultado.type) {
      case VoiceCommandType.abrirNovoProjeto:
        await _pararEscutaAntesDeNavegar();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirNovoProjeto(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirDashboard:
        await _pararEscutaAntesDeNavegar();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirDashboard(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirProjetos:
        await _pararEscutaAntesDeNavegar();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirProjetos(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.listarGravacoes:
        await _pararEscutaAntesDeNavegar();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirGravacoes(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirConfiguracoes:
        await _pararEscutaAntesDeNavegar();
        if (!context.mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirConfiguracoes();
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirAssistente:
        setState(() {
          _statusVoz = 'Assistente de voz ja esta ativo na tela inicial.';
        });
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.abrirHistorico:
        await _pararEscutaAntesDeNavegar();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        await _abrirHistorico(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.voltar:
        Navigator.maybePop(context);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.sair:
        await _pararEscutaAntesDeNavegar();
        if (mounted) {
          await _sair(context);
        }
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.ativarControleVoz:
      case VoiceCommandType.desativarControleVoz:
      case VoiceCommandType.ativarEscutaContinua:
      case VoiceCommandType.desativarEscutaContinua:
      case VoiceCommandType.ativarFeedbackSonoro:
      case VoiceCommandType.desativarFeedbackSonoro:
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
      case VoiceCommandType.desconhecido:
        setState(() {
          _iaPensando = false;
          _statusVoz = _commandController.aiConfigured
              ? 'Comando nao executavel nesta tela.'
              : 'Comando nao reconhecido. Configure GEMINI_API_KEY para NLU.';
        });
        _executandoComandoVoz = false;
        return;
    }
  }

  Future<void> _pararEscutaAntesDeNavegar() async {
    _escutaContinuaSuspensa = true;

    if (_ouvindo || _speechService.isListening) {
      await _speechService.cancelListening();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _ouvindo = false;
    });
  }

  Future<void> _abrirConfiguracoes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfiguracoesPage(usuario: widget.usuario),
      ),
    );

    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
    });

    await _retomarEscutaAposNavegacao();
  }

  Future<void> _retomarEscutaAposNavegacao() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
    });

    _escutaContinuaSuspensa = false;
    if (configuracao.comandosVozAtivos &&
        configuracao.escutaContinua &&
        !_ouvindo) {
      await _iniciarEscutaHome();
    }
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
            onPressed: _abrirConfiguracoes,
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
