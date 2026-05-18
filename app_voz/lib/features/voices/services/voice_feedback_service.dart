import 'package:flutter/services.dart';

import '../../../repositories/configuracao_app_repository.dart';
import 'command_service.dart';

abstract class VoiceFeedbackService {
  const VoiceFeedbackService();

  Future<void> notifyCommandResult(CommandResult result);
}

class SystemVoiceFeedbackService extends VoiceFeedbackService {
  SystemVoiceFeedbackService({
    ConfiguracaoAppRepository? configuracaoRepository,
  }) : _configuracaoRepository =
           configuracaoRepository ?? ConfiguracaoAppRepository.instance;

  final ConfiguracaoAppRepository _configuracaoRepository;

  @override
  Future<void> notifyCommandResult(CommandResult result) async {
    final configuracao = await _configuracaoRepository.buscarConfiguracao();

    if (!configuracao.feedbackSonoro) {
      return;
    }

    try {
      if (result.recognized) {
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.selectionClick();
      } else {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.lightImpact();
      }
    } catch (_) {
      // Feedback is optional; unsupported devices/tests must not break commands.
    }
  }
}

class NoopVoiceFeedbackService extends VoiceFeedbackService {
  const NoopVoiceFeedbackService();

  @override
  Future<void> notifyCommandResult(CommandResult result) async {}
}
