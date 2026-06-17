import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/comando_voz.dart';
import '../../../models/configuracao_app.dart';
import '../../../models/usuario.dart';
import '../../../repositories/comando_voz_repository.dart';
import '../../../repositories/configuracao_app_repository.dart';
import '../controllers/voice_command_controller.dart';
import '../services/command_service.dart';
import '../services/voice_global_command_service.dart';
import '../services/voice_recognition_error_guard.dart';
import 'voice_command_dispatcher.dart';
import 'voice_confirmation_controller.dart';
import 'voice_listening_coordinator.dart';
import 'voice_navigation_command_handler.dart';
import 'voice_route_observer.dart';
import 'voice_session_manager.dart';
import 'voice_session_state.dart';
import 'voice_state_machine.dart';

/// Escuta contínua + interpretação compartilhada para telas contextuais (Fase 2).
mixin ContextualVoiceListeningMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  final VoiceListeningCoordinator voiceCoordinator =
      VoiceListeningCoordinator.instance;
  final VoiceCommandController voiceCommandController =
      VoiceCommandController();
  final VoiceGlobalCommandService voiceGlobalCommandService =
      VoiceGlobalCommandService();
  final VoiceConfirmationController voiceConfirmationController =
      VoiceConfirmationController();
  final VoiceSessionManager voiceSessionManager = VoiceSessionManager.instance;
  final VoiceRecognitionErrorGuard voiceRecognitionErrorGuard =
      VoiceRecognitionErrorGuard();

  bool voiceOuvindo = false;
  bool voiceEscutaContinuaAtiva = false;
  bool voiceParadaManual = false;
  bool voiceExecutandoComando = false;
  bool voiceIaPensando = false;
  bool _voiceLifecycleObserverRegistered = false;
  bool _voiceRouteObserverRegistered = false;
  bool _voiceRouteActive = true;
  bool _voiceStartInProgress = false;
  bool _voiceRouteRecoveryAttempted = false;
  bool _voiceRecoveryPending = false;
  bool _voiceSpeechResultReceived = false;
  Future<void> _voiceRoutePausePending = Future<void>.value();
  AppLifecycleListener? _voiceLifecycleListener;
  PageRoute<dynamic>? _voiceRoute;
  String? voiceStatusMessage;
  VoiceSessionState voiceSessionState = const VoiceSessionState.idle();

  String get voiceOwnerId;

  int? get voiceUsuarioId;

  String get voiceListeningPrompt;

  String get voiceErrorPrompt => 'Não entendi. Pode repetir.';

  bool get voiceHandlesGlobalCommands => true;

  bool get voiceHandlesGlobalNavigationCommands => true;

  bool get voiceRegistersCommands => true;

  bool shouldUseAiForVoiceInput(String normalizedText) => true;

  VoiceNavigationCommandHandler? get voiceNavigationCommandHandler => null;

  /// Implementar com `@override late final` em [initState].
  VoiceCommandDispatcher get voiceCommandDispatcher;

  void onVoiceConfigurationChanged(ConfiguracaoApp configuracao) {}

  void voiceSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @visibleForTesting
  bool get voiceRouteActiveForTesting => _voiceRouteActive;

  @visibleForTesting
  bool get voiceRouteObserverRegisteredForTesting =>
      _voiceRouteObserverRegistered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeVoiceRouteObserver();
  }

  @override
  void didPush() {
    _voiceRouteActive = true;
    _voiceRouteRecoveryAttempted = false;
  }

  @override
  void didPushNext() {
    _voiceRouteActive = false;
    _voiceRouteRecoveryAttempted = false;
    _voiceRoutePausePending = pauseContextualVoiceForCoveredRoute();
  }

  @override
  void didPopNext() {
    _voiceRouteActive = true;
    _voiceRouteRecoveryAttempted = false;
    unawaited(_resumeContextualVoiceAfterRouteReturn());
  }

  @override
  void didPop() {
    _voiceRouteActive = false;
    _voiceRouteRecoveryAttempted = false;
  }

  void setVoiceSession(
    VoiceSessionPhase phase, {
    String? message,
    bool? listening,
    bool? thinking,
    bool? processing,
  }) {
    voiceSessionState = voiceSessionState.transitionTo(
      phase,
      message: message ?? voiceStatusMessage,
    );
    voiceOuvindo = listening ?? voiceSessionState.isListening;
    voiceIaPensando = thinking ?? voiceSessionState.isThinking;
    if (processing != null) {
      voiceExecutandoComando = processing;
    }
    voiceStatusMessage = voiceSessionState.message;
    voiceSessionManager.stateMachine.transitionTo(
      phase._toVoiceState(),
      ownerId: voiceOwnerId,
      message: voiceStatusMessage,
      reason: 'contextual_${phase.diagnosticName}',
      force: true,
    );
  }

  void scheduleVoiceListeningOnFirstFrame() {
    _ensureVoiceLifecycleObserver();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _voiceRouteActive) {
        unawaited(startContinuousVoiceListeningIfActive());
      }
    });
  }

  void disposeContextualVoiceListening() {
    voiceConfirmationController.clear();
    if (_voiceRouteObserverRegistered) {
      voiceRouteObserver.unsubscribe(this);
      _voiceRoute = null;
      _voiceRouteObserverRegistered = false;
    }
    if (_voiceLifecycleObserverRegistered) {
      _voiceLifecycleListener?.dispose();
      _voiceLifecycleListener = null;
      _voiceLifecycleObserverRegistered = false;
    }
    unawaited(voiceCoordinator.releaseAndStop(voiceOwnerId));
  }

  void _ensureVoiceLifecycleObserver() {
    if (_voiceLifecycleObserverRegistered) {
      return;
    }

    _voiceLifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!mounted || !_voiceRouteActive) {
          return;
        }

        unawaited(startContinuousVoiceListeningIfActive());
      },
    );
    _voiceLifecycleObserverRegistered = true;
  }

  void _subscribeVoiceRouteObserver() {
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic>) {
      return;
    }

    if (_voiceRouteObserverRegistered && identical(_voiceRoute, route)) {
      return;
    }

    if (_voiceRouteObserverRegistered) {
      voiceRouteObserver.unsubscribe(this);
    }

    _voiceRoute = route;
    voiceRouteObserver.subscribe(this, route);
    _voiceRouteObserverRegistered = true;
    _voiceRouteActive = route.isCurrent;
  }

  @visibleForTesting
  Future<void> pauseContextualVoiceForCoveredRoute() async {
    if (voiceSessionManager.activeOwnerId == voiceOwnerId ||
        voiceSessionManager.isSpeechListening) {
      await voiceSessionManager.cancelListening(
        ownerId: voiceOwnerId,
        reason: 'route_covered',
      );
    }
    voiceCoordinator.releaseOwner(voiceOwnerId);

    if (!mounted) {
      return;
    }

    voiceSetState(() {
      setVoiceSession(
        VoiceSessionPhase.idle,
        message: voiceStatusMessage,
        listening: false,
        thinking: false,
      );
    });
  }

  Future<void> _resumeContextualVoiceAfterRouteReturn() async {
    await _voiceRoutePausePending;
    if (!mounted || !_voiceRouteActive) {
      return;
    }
    _debugVoice(
      'route_return owner=$voiceOwnerId active=$_voiceRouteActive '
      'continuous=$voiceEscutaContinuaAtiva listening=$voiceOuvindo '
      'sessionOwner=${voiceSessionManager.activeOwnerId}',
    );
    await startContinuousVoiceListeningIfActive();
    if (!mounted ||
        !_voiceRouteActive ||
        _voiceRouteRecoveryAttempted ||
        voiceOuvindo ||
        voiceParadaManual ||
        voiceSessionManager.recordingActive) {
      return;
    }

    _voiceRouteRecoveryAttempted = true;
    voiceCoordinator.scheduleContinuousRestart(
      ownerId: voiceOwnerId,
      reason: VoiceRestartReason.normal,
      shouldRestart: () =>
          mounted &&
          _voiceRouteActive &&
          voiceEscutaContinuaAtiva &&
          !voiceParadaManual &&
          !voiceExecutandoComando &&
          !voiceOuvindo &&
          !voiceSessionManager.recordingActive,
      onRestart: startContextualVoiceListening,
    );
  }

  Future<void> toggleContextualVoiceListening() async {
    // Só executa STOP se o manager/STT estão realmente ouvindo.
    // Se voiceOuvindo=true mas o STT real está parado (estado stale),
    // cai no restart para recuperar a escuta em vez de parar nada.
    if (voiceOuvindo &&
        voiceSessionManager.activeOwnerId == voiceOwnerId &&
        voiceSessionManager.listeningActive) {
      voiceParadaManual = true;
      await voiceSessionManager.stopListening(voiceOwnerId, manual: true);
      if (!mounted) {
        return;
      }
      voiceSetState(() {
        setVoiceSession(
          VoiceSessionPhase.manualPaused,
          message: 'Escuta encerrada.',
          listening: false,
          thinking: false,
        );
      });
      return;
    }

    await restartContextualVoiceListeningManually();
  }

  @visibleForTesting
  Future<void> restartContextualVoiceListeningManually() async {
    _debugVoiceCommandFlow(
      'manualMicTap owner=$voiceOwnerId state=${voiceSessionState.phase.name} '
      'managerOwner=${voiceSessionManager.activeOwnerId} '
      'cooldown=${voiceSessionManager.isBusyCooldownActive}',
    );

    if (voiceExecutandoComando &&
        !voiceConfirmationController.hasPendingConfirmation) {
      _debugVoiceCommandFlow(
        'startRequested owner=$voiceOwnerId allowed=false '
        'reason=command_processing',
      );
      return;
    }

    _voiceRecoveryPending = false;
    voiceParadaManual = false;
    voiceSessionManager.cancelPendingRecovery(
      ownerId: voiceOwnerId,
      reason: 'manual_mic_tap',
    );
    _debugVoiceCommandFlow('forceReset reason=manual_mic_tap');
    await voiceSessionManager.forceResetListeningSession(
      ownerId: voiceOwnerId,
      reason: 'manual_mic_tap',
      clearBusyCooldown: true,
    );

    if (!mounted || !_voiceRouteActive) {
      return;
    }

    voiceSetState(() {
      setVoiceSession(
        VoiceSessionPhase.idle,
        message: 'Reativando microfone...',
        listening: false,
        thinking: false,
      );
    });

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || !_voiceRouteActive) {
      return;
    }
    await startContextualVoiceListening(manualOverride: true);
  }

  Future<void> startContinuousVoiceListeningIfActive() async {
    _ensureVoiceLifecycleObserver();
    if (!_voiceRouteActive || _voiceStartInProgress) {
      return;
    }

    _voiceStartInProgress = true;
    try {
      final configuracao = await ConfiguracaoAppRepository.instance
          .buscarConfiguracao();

      if (!mounted || !_voiceRouteActive) {
        return;
      }

      syncVoiceConfigFlags(configuracao);

      if (voiceEscutaContinuaAtiva && !voiceOuvindo && !voiceParadaManual) {
        await startContextualVoiceListening();
      }
    } finally {
      _voiceStartInProgress = false;
    }
  }

  void syncVoiceConfigFlags(ConfiguracaoApp configuracao) {
    voiceEscutaContinuaAtiva =
        configuracao.comandosVozAtivos && configuracao.escutaContinua;
  }

  Future<void> startContextualVoiceListening({
    bool manualOverride = false,
  }) async {
    _ensureVoiceLifecycleObserver();
    if (!_voiceRouteActive) {
      return;
    }

    if (voiceSessionManager.isListeningStartInProgress ||
        voiceSessionManager.isBusyCooldownActive) {
      if (manualOverride) {
        _debugVoiceCommandFlow(
          'startRequested owner=$voiceOwnerId allowed=false '
          'reason=manager_busy_after_manual_reset starting='
          '${voiceSessionManager.isListeningStartInProgress} cooldown='
          '${voiceSessionManager.isBusyCooldownActive}',
        );
      }
      _debugVoice(
        'start_ignored owner=$voiceOwnerId reason=busy startInProgress='
        '$_voiceStartInProgress managerStarting='
        '${voiceSessionManager.isListeningStartInProgress} cooldown='
        '${voiceSessionManager.isBusyCooldownActive}',
      );
      return;
    }

    if (voiceSessionManager.activeOwnerId == voiceOwnerId &&
        voiceSessionManager.listeningActive) {
      voiceSetState(() {
        setVoiceSession(
          VoiceSessionPhase.listening,
          message: voiceListeningPrompt,
          listening: true,
          thinking: false,
        );
      });
      return;
    }

    final configuracao = await ConfiguracaoAppRepository.instance
        .buscarConfiguracao();

    if (!mounted || !_voiceRouteActive) {
      return;
    }

    syncVoiceConfigFlags(configuracao);

    _voiceRecoveryPending = false;

    if (!configuracao.comandosVozAtivos) {
      voiceSetState(() {
        setVoiceSession(
          VoiceSessionPhase.manualPaused,
          message: 'Comandos de voz desativados.',
          listening: false,
          thinking: false,
        );
      });
      voiceSessionManager.markDisabled(
        ownerId: voiceOwnerId,
        reason: 'config_voice_disabled',
      );
      return;
    }

    voiceSetState(() {
      setVoiceSession(
        VoiceSessionPhase.listening,
        message: voiceListeningPrompt,
        listening: true,
        thinking: false,
      );
    });
    _debugVoiceCommandFlow(
      'startRequested owner=$voiceOwnerId allowed=true '
      'reason=${manualOverride ? 'manual' : 'continuous'}',
    );

    final started = await voiceSessionManager.startListening(
      ownerId: voiceOwnerId,
      onResult: (texto) {
        if (!_voiceRouteActive) {
          return;
        }
        // Sinalizar que resultado chegou antes de processContextualVoiceInput
        // iniciar — evita que recovery dispare na janela entre done e resultado.
        _voiceSpeechResultReceived = true;
        voiceRecognitionErrorGuard.reset();
        _debugVoiceCommandFlow('finalText="$texto" owner=$voiceOwnerId');
        unawaited(processContextualVoiceInput(texto));
      },
      onStatus: (status) {
        if (!mounted || !_voiceRouteActive) {
          return;
        }
        _debugVoiceCommandFlow('sttStatus=$status owner=$voiceOwnerId');

        if (status == 'done' || status == 'notListening') {
          if (voiceExecutandoComando || _voiceSpeechResultReceived) {
            _debugVoiceCommandFlow(
              'recoveryScheduled allowed=false '
              'reason=${voiceExecutandoComando ? 'command_processing' : 'result_pending'} '
              'status=$status owner=$voiceOwnerId',
            );
            return;
          }
          voiceSetState(() {
            setVoiceSession(
              VoiceSessionPhase.idle,
              message: voiceStatusMessage,
              listening: false,
              thinking: false,
            );
          });
          scheduleVoiceContinuousRestart();
        }
      },
      onError: (error) {
        if (!mounted || !_voiceRouteActive) {
          return;
        }

        final decision = voiceRecognitionErrorGuard.evaluate(error);
        if (!decision.shouldPresent) {
          return;
        }

        voiceSetState(() {
          setVoiceSession(
            VoiceSessionPhase.error,
            message: VoiceRecognitionErrorGuard.friendlyMessage,
            listening: false,
            thinking: false,
          );
        });
        if (decision.shouldRecover &&
            (error != 'error_busy' ||
                voiceSessionManager.recoveryAttempts == 0)) {
          scheduleVoiceContinuousRestart(reason: VoiceRestartReason.afterError);
        }
      },
    );

    if (!started) {
      if (!mounted) {
        return;
      }

      final decision = voiceRecognitionErrorGuard.evaluate('start_failed');
      if (decision.shouldPresent) {
        voiceSetState(() {
          setVoiceSession(
            VoiceSessionPhase.error,
            message: VoiceRecognitionErrorGuard.friendlyMessage,
            listening: false,
            thinking: false,
          );
        });
      }
      if (decision.shouldRecover && !voiceSessionManager.isBusyCooldownActive) {
        scheduleVoiceContinuousRestart(reason: VoiceRestartReason.afterError);
      }
    }
  }

  Future<void> processContextualVoiceInput(String texto) async {
    // Limpar latch de resultado imediatamente (antes de qualquer await).
    // Garante que onStatus 'done' posterior não seja bloqueado desnecessariamente.
    _voiceSpeechResultReceived = false;

    if (!_voiceRouteActive) {
      return;
    }

    if (voiceExecutandoComando &&
        !voiceConfirmationController.hasPendingConfirmation) {
      return;
    }

    _voiceRecoveryPending = false;
    voiceSessionManager.cancelPendingRecovery(
      ownerId: voiceOwnerId,
      reason: 'command_processing',
    );
    voiceExecutandoComando = true;
    voiceSessionManager.markProcessing(
      ownerId: voiceOwnerId,
      message: voiceStatusMessage,
    );
    voiceSessionState = voiceSessionState.transitionTo(
      VoiceSessionPhase.processingCommand,
      message: voiceStatusMessage,
    );

    final resultadoController = await voiceCommandController.interpret(
      texto,
      usuarioId: voiceUsuarioId,
      aiEnabled: shouldUseAiForVoiceInput(
        const CommandService().normalize(texto),
      ),
      onAiStarted: () {
        voiceSetState(() {
          setVoiceSession(
            VoiceSessionPhase.aiThinking,
            message: 'IA pensando...',
            listening: false,
            thinking: true,
            processing: true,
          );
        });
      },
    );
    final resultado = resultadoController.commandResult;
    _debugVoiceCommandFlow(
      'normalized="${resultado.normalizedText}" '
      'source=${resultadoController.source.name} '
      'type=${resultado.type.name} owner=$voiceOwnerId',
    );
    _debugVoice(
      'recognized owner=$voiceOwnerId raw="$texto" '
      'normalized="${resultado.normalizedText}" type=${resultado.type.name} '
      'recognized=${resultado.recognized} usedAi=${resultadoController.usedAi}',
    );

    if (voiceRegistersCommands) {
      unawaited(registerVoiceCommand(resultado));
    }

    if (!mounted || !_voiceRouteActive || resultado.normalizedText.isEmpty) {
      voiceExecutandoComando = false;
      voiceIaPensando = false;
      voiceSessionState = voiceSessionState.transitionTo(
        VoiceSessionPhase.idle,
        message: voiceStatusMessage,
      );
      return;
    }

    voiceSetState(() {
      setVoiceSession(
        VoiceSessionPhase.processingCommand,
        message: voiceStatusMessage,
        listening: false,
        thinking: false,
        processing: true,
      );
    });

    final confirmationResult = await voiceConfirmationController.handle(
      resultado,
    );
    if (confirmationResult.handled) {
      _debugVoice(
        'decision owner=$voiceOwnerId type=${resultado.type.name} '
        'target=confirmation action=${confirmationResult.action.name}',
      );
      if (mounted && confirmationResult.message.isNotEmpty) {
        voiceSetState(() {
          voiceStatusMessage = confirmationResult.message;
        });
      }
      voiceExecutandoComando = false;
      voiceIaPensando = false;
      voiceSessionState = voiceSessionState.transitionTo(
        VoiceSessionPhase.idle,
        message: voiceStatusMessage,
      );
      scheduleVoiceContinuousRestart();
      return;
    }

    if (voiceHandlesGlobalCommands) {
      final globalResult = await voiceGlobalCommandService.execute(resultado);
      if (!_voiceRouteActive) {
        voiceExecutandoComando = false;
        voiceIaPensando = false;
        return;
      }
      if (globalResult.handled) {
        _debugVoice(
          'decision owner=$voiceOwnerId type=${resultado.type.name} '
          'target=global stop=${globalResult.shouldStopListening}',
        );
        voiceSessionManager.markExecuting(
          ownerId: voiceOwnerId,
          message: globalResult.message,
        );
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
        voiceSessionState = voiceSessionState.transitionTo(
          VoiceSessionPhase.idle,
          message: voiceStatusMessage,
        );
        if (!globalResult.shouldStopListening) {
          scheduleVoiceContinuousRestart();
        }
        return;
      }
    }

    if (voiceHandlesGlobalNavigationCommands) {
      final navigationResult = await voiceNavigationCommandHandler?.handle(
        resultado,
      );
      if (!_voiceRouteActive) {
        voiceExecutandoComando = false;
        voiceIaPensando = false;
        return;
      }
      if (navigationResult != null) {
        _debugVoice(
          'decision owner=$voiceOwnerId type=${resultado.type.name} '
          'target=navigation handled=${navigationResult.handled}',
        );
        await _completePageCommandResult(navigationResult);
        return;
      }
    }

    voiceSessionManager.markExecuting(
      ownerId: voiceOwnerId,
      message: voiceStatusMessage,
    );
    final pageResult = await voiceCommandDispatcher.dispatch(resultado);
    _debugVoice(
      'decision owner=$voiceOwnerId type=${resultado.type.name} '
      'target=page handled=${pageResult.handled}',
    );
    if (!_voiceRouteActive) {
      voiceExecutandoComando = false;
      voiceIaPensando = false;
      return;
    }

    await _completePageCommandResult(pageResult);
  }

  Future<void> _completePageCommandResult(
    VoiceCommandPageResult pageResult,
  ) async {
    if (pageResult.statusMessage != null) {
      voiceSetState(() {
        voiceStatusMessage = pageResult.statusMessage;
      });
    }

    if (pageResult.suspendListening) {
      await suspendContextualVoiceListening();
    }

    voiceExecutandoComando = false;
    voiceSessionState = voiceSessionState.transitionTo(
      VoiceSessionPhase.idle,
      message: voiceStatusMessage,
    );

    if (pageResult.restartListening) {
      scheduleVoiceContinuousRestart();
    }
  }

  void scheduleVoiceContinuousRestart({
    VoiceRestartReason reason = VoiceRestartReason.normal,
  }) {
    if (_voiceRecoveryPending ||
        _voiceStartInProgress ||
        voiceSessionManager.isListeningStartInProgress ||
        (reason == VoiceRestartReason.normal &&
            voiceSessionManager.isBusyCooldownActive)) {
      _debugVoiceCommandFlow(
        'recoveryScheduled allowed=false reason=${reason.name} '
        'pending=$_voiceRecoveryPending startInProgress=$_voiceStartInProgress '
        'managerStarting=${voiceSessionManager.isListeningStartInProgress} '
        'busyCooldown=${voiceSessionManager.isBusyCooldownActive}',
      );
      _debugVoice(
        'recovery_ignored owner=$voiceOwnerId reason=${reason.name} '
        'pending=$_voiceRecoveryPending startInProgress=$_voiceStartInProgress '
        'managerStarting=${voiceSessionManager.isListeningStartInProgress} '
        'cooldown=${voiceSessionManager.isBusyCooldownActive}',
      );
      return;
    }

    _voiceRecoveryPending = true;
    _debugVoiceCommandFlow(
      'recoveryScheduled allowed=true reason=${reason.name} owner=$voiceOwnerId',
    );
    voiceCoordinator.scheduleContinuousRestart(
      ownerId: voiceOwnerId,
      reason: reason,
      shouldRestart: () {
        final canRestart = mounted &&
            _voiceRouteActive &&
            voiceEscutaContinuaAtiva &&
            !voiceParadaManual &&
            !voiceExecutandoComando &&
            !voiceOuvindo &&
            !voiceSessionManager.isListeningStartInProgress &&
            !voiceSessionManager.isBusyCooldownActive;
        // Liberar latch quando condição não é atendida para não bloquear
        // futuros agendamentos quando o estado mudar.
        if (!canRestart) {
          _voiceRecoveryPending = false;
        }
        return canRestart;
      },
      onRestart: () async {
        _voiceRecoveryPending = false;
        _debugVoiceCommandFlow(
          'recoveryCancelled reason=restart_running owner=$voiceOwnerId',
        );
        await startContextualVoiceListening();
      },
    );
  }

  Future<void> suspendContextualVoiceListening({
    bool keepManualPause = false,
  }) async {
    voiceParadaManual = keepManualPause;
    if (keepManualPause) {
      voiceEscutaContinuaAtiva = false;
    }

    if (voiceOuvindo || voiceSessionManager.isSpeechListening) {
      await voiceSessionManager.cancelListening(
        ownerId: voiceOwnerId,
        reason: keepManualPause ? 'manual_pause' : 'suspend',
      );
    }
    voiceCoordinator.releaseOwner(voiceOwnerId);

    voiceSetState(() {
      setVoiceSession(
        keepManualPause
            ? VoiceSessionPhase.manualPaused
            : VoiceSessionPhase.idle,
        message: voiceStatusMessage,
        listening: false,
        thinking: false,
      );
    });
  }

  Future<bool> showVoiceConfirmationDialog({
    required String id,
    required String title,
    required String message,
    String confirmLabel = 'Confirmar',
    String cancelLabel = 'Cancelar',
    bool destructive = false,
  }) async {
    var completedByVoice = false;

    voiceExecutandoComando = false;
    voiceIaPensando = false;
    voiceSessionState = voiceSessionState.transitionTo(
      VoiceSessionPhase.idle,
      message: voiceStatusMessage,
    );
    scheduleVoiceContinuousRestart();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        voiceConfirmationController.register(
          VoiceConfirmationRequest(
            id: id,
            description: title,
            onConfirm: () {
              completedByVoice = true;
              Navigator.pop(dialogContext, true);
            },
            onCancel: () {
              completedByVoice = true;
              Navigator.pop(dialogContext, false);
            },
            destructive: destructive,
          ),
        );

        return AlertDialog(
          title: Text(title),
          content: Text(
            '$message\n\nDiga "confirmar" para continuar ou "cancelar" para voltar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(cancelLabel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: destructive
                  ? ElevatedButton.styleFrom(backgroundColor: Colors.red)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    if (!completedByVoice) {
      voiceConfirmationController.clear();
    }

    if (mounted &&
        _voiceRouteActive &&
        voiceEscutaContinuaAtiva &&
        !voiceOuvindo &&
        !voiceParadaManual) {
      await startContextualVoiceListening();
    }

    return result ?? false;
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

  void _debugVoice(String message) {
    assert(() {
      debugPrint('[VoiceH8] $message');
      return true;
    }());
  }

  void _debugVoiceCommandFlow(String message) {
    assert(() {
      debugPrint('[VoiceCommandFlow] $message');
      return true;
    }());
  }
}

extension on VoiceSessionPhase {
  VoiceState _toVoiceState() {
    return switch (this) {
      VoiceSessionPhase.idle => VoiceState.idle,
      VoiceSessionPhase.listening => VoiceState.listening,
      VoiceSessionPhase.processingCommand => VoiceState.processing,
      VoiceSessionPhase.aiThinking => VoiceState.processing,
      VoiceSessionPhase.manualPaused => VoiceState.paused,
      VoiceSessionPhase.recordingLocked => VoiceState.recording,
      VoiceSessionPhase.error => VoiceState.error,
    };
  }
}
