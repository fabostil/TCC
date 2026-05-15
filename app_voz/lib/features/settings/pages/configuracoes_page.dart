import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../core/ui/voice_status_bar.dart';
import '../../../models/comando_voz.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../../voices/controllers/voice_command_controller.dart';
import '../../voices/services/command_service.dart';
import '../../voices/services/speech_service.dart';

class ConfiguracoesPage extends StatefulWidget {
  final Usuario? usuario;

  const ConfiguracoesPage({super.key, this.usuario});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final SpeechService _speechService = SpeechService();
  final VoiceCommandController _commandController = VoiceCommandController();
  bool _carregando = true;
  bool _ouvindo = false;
  bool _escutaContinuaAtiva = false;
  bool _paradaManualEscuta = false;
  bool _executandoComandoVoz = false;
  ConfiguracaoApp? _configuracao;
  String? _statusVoz;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracao();
  }

  Future<void> _carregarConfiguracao() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    setState(() {
      _configuracao = configuracao;
      _carregando = false;
    });

    _escutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;
    if (_escutaContinuaAtiva && !_ouvindo && !_paradaManualEscuta) {
      await _iniciarEscutaVoz();
    }
  }

  Future<void> _salvar(ConfiguracaoApp configuracao) async {
    setState(() {
      _configuracao = configuracao;
    });

    await ConfiguracaoAppRepository.instance.salvarConfiguracao(configuracao);
  }

  Future<void> _alternarEscutaVoz() async {
    if (_ouvindo) {
      _paradaManualEscuta = true;
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

    _paradaManualEscuta = false;
    await _iniciarEscutaVoz();
  }

  Future<void> _iniciarEscutaVoz() async {
    final configuracao =
        _configuracao ??
        await ConfiguracaoAppRepository.instance.buscarConfiguracao();

    if (!mounted) {
      return;
    }

    _escutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;

    if (!configuracao.comandosVozAtivos) {
      setState(() {
        _statusVoz = 'Comandos de voz desativados.';
      });
      return;
    }

    setState(() {
      _ouvindo = true;
      _statusVoz = 'Ouvindo comando de configuracao...';
    });

    await _speechService.startListening(
      onResult: (texto) {
        unawaited(_executarComandoVoz(texto));
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _ouvindo = false;
          });
          _reiniciarEscutaContinuaSeNecessario();
        }
      },
      onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _ouvindo = false;
          _statusVoz = 'Erro no reconhecimento de voz: $error';
        });
        _reiniciarEscutaContinuaSeNecessario();
      },
    );
  }

  Future<void> _executarComandoVoz(String texto) async {
    if (_executandoComandoVoz) {
      return;
    }

    _executandoComandoVoz = true;
    final resultadoController = await _commandController.interpret(texto);
    final resultado = resultadoController.commandResult;

    unawaited(_registrarComando(resultado));

    if (!mounted || resultado.normalizedText.isEmpty) {
      _executandoComandoVoz = false;
      return;
    }

    final configuracao = _configuracao;
    if (configuracao == null) {
      _executandoComandoVoz = false;
      return;
    }

    switch (resultado.type) {
      case VoiceCommandType.ativarControleVoz:
        await _salvar(configuracao.copyWith(comandosVozAtivos: true));
        _atualizarStatus('Controle por voz ativado.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.desativarControleVoz:
        await _salvar(
          configuracao.copyWith(
            comandosVozAtivos: false,
            escutaContinua: false,
          ),
        );
        _atualizarStatus('Controle por voz desativado.');
        await _suspenderEscutaParaAcao(manterPausada: true);
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.ativarEscutaContinua:
        await _salvar(
          configuracao.copyWith(comandosVozAtivos: true, escutaContinua: true),
        );
        _atualizarStatus('Escuta continua ativada.');
        _escutaContinuaAtiva = true;
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.desativarEscutaContinua:
        await _salvar(configuracao.copyWith(escutaContinua: false));
        _atualizarStatus('Escuta continua desativada.');
        _escutaContinuaAtiva = false;
        _executandoComandoVoz = false;
        return;
      case VoiceCommandType.ativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: true));
        _atualizarStatus('Feedback sonoro ativado.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.desativarFeedbackSonoro:
        await _salvar(configuracao.copyWith(feedbackSonoro: false));
        _atualizarStatus('Feedback sonoro desativado.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.ativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: true));
        _atualizarStatus('Parada por silencio ativada.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.desativarParadaSilencio:
        await _salvar(configuracao.copyWith(paradaSilencio: false));
        _atualizarStatus('Parada por silencio desativada.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.definirTempoSilencio:
        final segundos = int.tryParse(resultado.parametro ?? '');
        if (segundos == null) {
          _atualizarStatus('Diga o tempo de silencio entre 3 e 12 segundos.');
          _executandoComandoVoz = false;
          _reiniciarEscutaContinuaSeNecessario();
          return;
        }
        await _salvar(
          configuracao.copyWith(
            paradaSilencio: true,
            tempoSilencioSegundos: segundos.clamp(3, 12).toInt(),
          ),
        );
        _atualizarStatus('Tempo de silencio definido para $segundos segundos.');
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
      case VoiceCommandType.voltar:
        await _suspenderEscutaParaAcao();
        if (!mounted) {
          _executandoComandoVoz = false;
          return;
        }
        Navigator.maybePop(context);
        _executandoComandoVoz = false;
        return;
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
        _atualizarStatus(
          resultado.recognized
              ? 'Comando nao disponivel nesta tela.'
              : 'Comando nao reconhecido nesta tela.',
        );
        _executandoComandoVoz = false;
        _reiniciarEscutaContinuaSeNecessario();
        return;
    }
  }

  void _reiniciarEscutaContinuaSeNecessario() {
    if (!_escutaContinuaAtiva ||
        _paradaManualEscuta ||
        _executandoComandoVoz ||
        !mounted) {
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted ||
          _ouvindo ||
          _paradaManualEscuta ||
          _executandoComandoVoz ||
          !_escutaContinuaAtiva) {
        return;
      }

      unawaited(_iniciarEscutaVoz());
    });
  }

  Future<void> _suspenderEscutaParaAcao({bool manterPausada = false}) async {
    _paradaManualEscuta = manterPausada;
    _escutaContinuaAtiva = false;

    if (_ouvindo || _speechService.isListening) {
      await _speechService.cancelListening();
    }

    if (mounted) {
      setState(() {
        _ouvindo = false;
      });
    }
  }

  void _atualizarStatus(String status) {
    if (!mounted) {
      return;
    }

    setState(() {
      _statusVoz = status;
    });
  }

  Future<void> _registrarComando(CommandResult resultado) async {
    final usuarioId = widget.usuario?.id;
    if (usuarioId == null || resultado.normalizedText.isEmpty) {
      return;
    }

    try {
      await ComandoVozRepository.instance.registrarComando(
        ComandoVoz(
          usuarioId: usuarioId,
          textoReconhecido: resultado.originalText,
          tipoComando: resultado.tipoComando,
          statusReconhecimento: resultado.statusReconhecimento,
          acaoExecutada: resultado.acaoExecutada,
          dataHora: DateTime.now().toIso8601String(),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao registrar comando de voz: $e');
    }
  }

  @override
  void dispose() {
    _speechService.stopListening();
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
            tooltip: _ouvindo ? 'Parar escuta' : 'Comando de voz',
            onPressed: _alternarEscutaVoz,
            icon: Icon(_ouvindo ? Icons.mic : Icons.mic_none),
          ),
        ],
      ),
      body: _carregando || configuracao == null
          ? const AppLoadingView(message: 'Carregando configurações...')
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
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
                  onChanged: (value) =>
                      _salvar(configuracao.copyWith(comandosVozAtivos: value)),
                ),
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
      bottomNavigationBar: _statusVoz == null
          ? null
          : VoiceStatusBar(message: _statusVoz!, listening: _ouvindo),
    );
  }
}
