import 'package:flutter/material.dart';

import '../../../core/ui/app_loading_view.dart';
import '../../../core/ui/app_spacing.dart';
import '../../../models/configuracao_app.dart';
import '../../../repositories/configuracao_app_repository.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  bool _carregando = true;
  ConfiguracaoApp? _configuracao;

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
  }

  Future<void> _salvar(ConfiguracaoApp configuracao) async {
    setState(() {
      _configuracao = configuracao;
    });

    await ConfiguracaoAppRepository.instance.salvarConfiguracao(configuracao);
  }

  @override
  Widget build(BuildContext context) {
    final configuracao = _configuracao;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
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
    );
  }
}
