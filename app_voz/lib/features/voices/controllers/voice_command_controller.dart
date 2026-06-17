import '../services/ai_command_service.dart';
import '../services/command_service.dart';
import '../services/custom_command_service.dart';
import '../services/voice_feedback_service.dart';

class VoiceCommandControllerResult {
  const VoiceCommandControllerResult({
    required this.commandResult,
    required this.usedAi,
    required this.aiConfigured,
  });

  final CommandResult commandResult;
  final bool usedAi;
  final bool aiConfigured;
}

class VoiceCommandController {
  VoiceCommandController({
    CommandService commandService = const CommandService(),
    AiCommandService? aiCommandService,
    CustomCommandService? customCommandService,
    VoiceFeedbackService? feedbackService,
  }) : _commandService = commandService,
       _aiCommandService = aiCommandService ?? AiCommandService(),
       _customCommandService = customCommandService ?? CustomCommandService(),
       _feedbackService = feedbackService ?? SystemVoiceFeedbackService();

  final CommandService _commandService;
  final AiCommandService _aiCommandService;
  final CustomCommandService _customCommandService;
  final VoiceFeedbackService _feedbackService;

  bool get aiConfigured => _aiCommandService.isConfigured;

  Future<VoiceCommandControllerResult> interpret(
    String text, {
    int? usuarioId,
    bool aiEnabled = true,
    void Function()? onAiStarted,
  }) async {
    var result = _commandService.interpret(text);

    if (result.normalizedText.isEmpty) {
      await _feedbackService.notifyCommandResult(result);
      return VoiceCommandControllerResult(
        commandResult: result,
        usedAi: false,
        aiConfigured: aiConfigured,
      );
    }

    if (result.recognized) {
      await _feedbackService.notifyCommandResult(result);
      return VoiceCommandControllerResult(
        commandResult: result,
        usedAi: false,
        aiConfigured: aiConfigured,
      );
    }

    if (usuarioId != null) {
      final customResult = await _customCommandService.interpret(
        usuarioId: usuarioId,
        originalText: text,
        normalizedText: result.normalizedText,
      );

      if (customResult.recognized) {
        await _feedbackService.notifyCommandResult(customResult);
        return VoiceCommandControllerResult(
          commandResult: customResult,
          usedAi: false,
          aiConfigured: aiConfigured,
        );
      }
    }

    if (!aiEnabled || !aiConfigured) {
      await _feedbackService.notifyCommandResult(result);
      return VoiceCommandControllerResult(
        commandResult: result,
        usedAi: false,
        aiConfigured: aiConfigured,
      );
    }

    onAiStarted?.call();
    result = await _aiCommandService.interpretUnknown(text);
    await _feedbackService.notifyCommandResult(result);

    return VoiceCommandControllerResult(
      commandResult: result,
      usedAi: true,
      aiConfigured: aiConfigured,
    );
  }
}
