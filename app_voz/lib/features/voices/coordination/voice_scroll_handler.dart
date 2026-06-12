import 'package:flutter/material.dart';

import '../services/command_service.dart';
import 'voice_command_dispatcher.dart';

class VoiceScrollHandler {
  const VoiceScrollHandler({required ScrollController controller})
    : _controller = controller;

  static const double viewportScrollFactor = 0.75;
  static const Duration animationDuration = Duration(milliseconds: 260);

  final ScrollController _controller;

  Future<VoiceCommandPageResult?> handle(CommandResult result) async {
    final direction = VoiceScrollDirection.fromCommand(result.type);
    if (direction == null) {
      return null;
    }

    if (!_controller.hasClients) {
      return VoiceCommandPageResult.handled(
        message: 'Não há lista para rolar nesta tela.',
      );
    }

    final position = _controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent) {
      return VoiceCommandPageResult.handled(
        message: 'Não há lista para rolar nesta tela.',
      );
    }

    final current = position.pixels;
    final target = switch (direction) {
      VoiceScrollDirection.down =>
        current + (position.viewportDimension * viewportScrollFactor),
      VoiceScrollDirection.up =>
        current - (position.viewportDimension * viewportScrollFactor),
      VoiceScrollDirection.top => position.minScrollExtent,
      VoiceScrollDirection.bottom => position.maxScrollExtent,
    };
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((clamped - current).abs() < 0.5) {
      return VoiceCommandPageResult.handled(
        message:
            direction == VoiceScrollDirection.up ||
                direction == VoiceScrollDirection.top
            ? 'Você já está no topo.'
            : 'Você já chegou ao fim da lista.',
      );
    }

    await _controller.animateTo(
      clamped.toDouble(),
      duration: animationDuration,
      curve: Curves.easeOutCubic,
    );

    return VoiceCommandPageResult.handled(message: direction.feedbackMessage);
  }
}

enum VoiceScrollDirection {
  down,
  up,
  top,
  bottom;

  static VoiceScrollDirection? fromCommand(VoiceCommandType type) {
    return switch (type) {
      VoiceCommandType.scrollBaixo => VoiceScrollDirection.down,
      VoiceCommandType.scrollCima => VoiceScrollDirection.up,
      VoiceCommandType.scrollTopo => VoiceScrollDirection.top,
      VoiceCommandType.scrollFim => VoiceScrollDirection.bottom,
      _ => null,
    };
  }

  String get feedbackMessage {
    return switch (this) {
      VoiceScrollDirection.down => 'Rolando para baixo.',
      VoiceScrollDirection.up => 'Rolando para cima.',
      VoiceScrollDirection.top => 'Indo para o topo.',
      VoiceScrollDirection.bottom => 'Indo para o fim da lista.',
    };
  }
}
