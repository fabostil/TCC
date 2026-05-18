import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/comando_voz.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../controllers/voice_command_controller.dart';
import '../services/command_service.dart';
import '../services/speech_service.dart';
import '../services/voice_global_command_service.dart';
import 'voice_command_dispatcher.dart';
import 'voice_listening_coordinator.dart';

/// Escuta contínua + interpretação compartilhada para telas contextuais (Fase 2).
mixin ContextualVoiceListeningMixin<T extends StatefulWidget> on State<T> {
  final SpeechService speechService = SpeechService.instance;
  final VoiceListeningCoordinator voiceCoordinator =
      VoiceListeningCoordinator.instance;
  final VoiceCommandController voiceCommandController =
      VoiceCommandController();
  final VoiceGlobalCommandService voiceGlobalCommandService =
      VoiceGlobalCommandService();

  bool voiceOuvindo = false;
  bool voiceEscutaContinuaAtiva = false;
  bool voiceParadaManual = false;
  bool voiceExecutandoComando = false;
  bool voiceIaPensando = false;
  String? voiceStatusMessage;

  String get voiceOwnerId;

  int? get voiceUsuarioId;

  String get voiceListeningPrompt;

  String get voiceErrorPrompt => 'Nao entendi. Pode repetir.';

  bool get voiceHandlesGlobalCommands => true;

  bool get voiceRegistersCommands => true;

  /// Implementar com `@override late final` em [initState].
  VoiceCommandDispatcher get voiceCommandDispatcher;

  void onVoiceConfigurationChanged(ConfiguracaoApp configuracao) {}

  void voiceSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void scheduleVoiceListeningOnFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(startContinuousVoiceListeningIfActive());
      }
    });
  }

  void disposeContextualVoiceListening() {
    unawaited(voiceCoordinator.releaseAndStop(voiceOwnerId));
  }

  Future<void> toggleContextualVoiceListening() async {
    if (voiceOuvindo) {
      voiceParadaManual = true;
      await speechService.stopListening();
      if (!mounted) {
        return;
      }
      voiceSetState(() {
        voiceOuvindo = false;
        voiceStatusMessage = 'Escuta encerrada.';
      });
      return;
    }

    voiceParadaManual = false;
    await startContextualVoiceListening();
  }

  Future<void> startContinuousVoiceListeningIfActive() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    syncVoiceConfigFlags(configuracao);

    if (voiceEscutaContinuaAtiva && !voiceOuvindo && !voiceParadaManual) {
      await startContextualVoiceListening();
    }
  }

  void syncVoiceConfigFlags(ConfiguracaoApp configuracao) {
    voiceEscutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;
  }

  Future<void> startContextualVoiceListening() async {
    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted) {
      return;
    }

    syncVoiceConfigFlags(configuracao);

    if (!configuracao.comandosVozAtivos) {
      voiceSetState(() {
        voiceStatusMessage = 'Comandos de voz desativados.';
      });
      return;
    }

    if (!voiceCoordinator.claimListening(voiceOwnerId)) {
      return;
    }

    voiceSetState(() {
      voiceOuvindo = true;
      voiceStatusMessage = voiceListeningPrompt;
    });

    await speechService.startListening(
      onResult: (texto) {
        unawaited(processContextualVoiceInput(texto));
      },
      onStatus: (status) {
        if (!mounted) {
          return;
        }

        if (status == 'done' || status == 'notListening') {
          voiceSetState(() {
            voiceOuvindo = false;
          });
          scheduleVoiceContinuousRestart();
        }
      },
      onError: (_) {
        if (!mounted) {
          return;
        }

        voiceSetState(() {
          voiceOuvindo = false;
          voiceStatusMessage = voiceErrorPrompt;
        });
        scheduleVoiceContinuousRestart(reason: VoiceRestartReason.afterError);
      },
    );
  }

  Future<void> processContextualVoiceInput(String texto) async {
    if (voiceExecutandoComando) {
      return;
    }

    voiceExecutandoComando = true;

    final resultadoController = await voiceCommandController.interpret(
      texto,
      usuarioId: voiceUsuarioId,
      onAiStarted: () {
        voiceSetState(() {
          voiceIaPensando = true;
          voiceStatusMessage = 'IA pensando...';
        });
      },
    );
    final resultado = resultadoController.commandResult;

    if (voiceRegistersCommands) {
      unawaited(registerVoiceCommand(resultado));
    }

    if (!mounted || resultado.normalizedText.isEmpty) {
      voiceExecutandoComando = false;
      voiceIaPensando = false;
      return;
    }

    voiceSetState(() {
      voiceIaPensando = false;
    });

    if (voiceHandlesGlobalCommands) {
      final globalResult = await voiceGlobalCommandService.execute(resultado);
      if (globalResult.handled) {
        final updatedConfig = globalResult.updatedConfig;
        if (updatedConfig != null) {
          syncVoiceConfigFlags(updatedConfig);
          onVoiceConfigurationChanged(updatedConfig);
        }

        if (globalResult.shouldStopListening) {
          await suspendContextualVoiceListening(keepManualPause: true);
        }

        if (mounted && globalResult.message != null) {
          voiceSetState(() {
            voiceStatusMessage = globalResult.message;
          });
        }

        voiceExecutandoComando = false;
        if (!globalResult.shouldStopListening) {
          scheduleVoiceContinuousRestart();
        }
        return;
      }
    }

    final pageResult = await voiceCommandDispatcher.dispatch(resultado);

    if (pageResult.statusMessage != null) {
      voiceSetState(() {
        voiceStatusMessage = pageResult.statusMessage;
      });
    }

    if (pageResult.suspendListening) {
      await suspendContextualVoiceListening();
    }

    voiceExecutandoComando = false;

    if (pageResult.restartListening) {
      scheduleVoiceContinuousRestart();
    }
  }

  void scheduleVoiceContinuousRestart({
    VoiceRestartReason reason = VoiceRestartReason.normal,
  }) {
    voiceCoordinator.scheduleContinuousRestart(
      ownerId: voiceOwnerId,
      reason: reason,
      shouldRestart: () =>
          mounted &&
          voiceEscutaContinuaAtiva &&
          !voiceParadaManual &&
          !voiceExecutandoComando &&
          !voiceOuvindo,
      onRestart: startContextualVoiceListening,
    );
  }

  Future<void> suspendContextualVoiceListening({
    bool keepManualPause = false,
  }) async {
    voiceParadaManual = keepManualPause;
    voiceEscutaContinuaAtiva = false;

    if (voiceOuvindo || speechService.isListening) {
      await speechService.cancelListening();
    }
    voiceCoordinator.releaseOwner(voiceOwnerId);

    voiceSetState(() {
      voiceOuvindo = false;
    });
  }

  Future<void> registerVoiceCommand(CommandResult resultado) async {
    final usuarioId = voiceUsuarioId;
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

  /// Helper para páginas com [Usuario].
  int? usuarioIdOf(Usuario? usuario) => usuario?.id;
}
