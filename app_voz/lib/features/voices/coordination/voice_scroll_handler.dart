import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
      // Aguarda um frame: o controller pode ainda estar se conectando ao
      // widget após uma navegação ou rebuild recente.
      await SchedulerBinding.instance.endOfFrame;
      if (!_controller.hasClients) {
        return VoiceCommandPageResult.handled(
          message: 'Não há mais conteúdo para rolar.',
        );
      }
    }

    final position = _controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent) {
      return VoiceCommandPageResult.handled(
        message: 'Não há mais conteúdo para rolar.',
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
            : 'Você já está no fim da lista.',
      );
    }

    await _animateTo(clamped.toDouble());

    if (direction == VoiceScrollDirection.bottom) {
      await _adjustToLatestBottomIfNeeded();
    }

    return VoiceCommandPageResult.handled(message: direction.feedbackMessage);
  }

  Future<void> _animateTo(double target) {
    return _controller.animateTo(
      target,
      duration: animationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _adjustToLatestBottomIfNeeded() async {
    if (!_controller.hasClients) {
      return;
    }

    final position = _controller.position;
    final latestBottom = position.maxScrollExtent;
    final current = position.pixels;
    if ((latestBottom - current).abs() < 0.5) {
      return;
    }

    await _animateTo(latestBottom);
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
