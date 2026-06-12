import '../services/command_service.dart';

/// Resultado da execução contextual de um comando de voz.
class VoiceCommandPageResult {
  const VoiceCommandPageResult._({
    required this.handled,
    this.statusMessage,
    this.restartListening = false,
    this.suspendListening = false,
  });

  final bool handled;
  final String? statusMessage;
  final bool restartListening;
  final bool suspendListening;

  factory VoiceCommandPageResult.handled({
    String? message,
    bool restartListening = true,
  }) {
    return VoiceCommandPageResult._(
      handled: true,
      statusMessage: message,
      restartListening: restartListening,
    );
  }

  factory VoiceCommandPageResult.navigateAway({String? message}) {
    return VoiceCommandPageResult._(
      handled: true,
      statusMessage: message,
      suspendListening: true,
      restartListening: false,
    );
  }

  factory VoiceCommandPageResult.unavailable({required bool recognized}) {
    return VoiceCommandPageResult._(
      handled: true,
      statusMessage: recognized
          ? 'Comando nao disponivel nesta tela.'
          : 'Comando nao reconhecido nesta tela.',
      restartListening: true,
    );
  }
}

typedef VoiceCommandHandler =
    Future<VoiceCommandPageResult> Function(CommandResult result);

/// Mapa de [VoiceCommandType] para handlers por tela (Fase 2).
class VoiceCommandDispatcher {
  VoiceCommandDispatcher({
    Map<VoiceCommandType, VoiceCommandHandler>? handlers,
    VoiceCommandHandler? onFallback,
  }) : _handlers = handlers ?? {},
       _onFallback = onFallback;

  final Map<VoiceCommandType, VoiceCommandHandler> _handlers;
  final VoiceCommandHandler? _onFallback;

  Future<VoiceCommandPageResult> dispatch(CommandResult result) async {
    final handler = _handlers[result.type];
    if (handler != null) {
      return handler(result);
    }

    final onFallback = _onFallback;
    if (onFallback != null) {
      return onFallback(result);
    }

    return VoiceCommandPageResult.unavailable(recognized: result.recognized);
  }
}
