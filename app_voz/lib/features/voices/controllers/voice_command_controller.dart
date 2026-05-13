import '../services/ai_command_service.dart';
import '../services/command_service.dart';

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
  }) : _commandService = commandService,
       _aiCommandService = aiCommandService ?? AiCommandService();

  final CommandService _commandService;
  final AiCommandService _aiCommandService;

  bool get aiConfigured => _aiCommandService.isConfigured;

  Future<VoiceCommandControllerResult> interpret(
    String text, {
    void Function()? onAiStarted,
  }) async {
    var result = _commandService.interpret(text);

    if (result.normalizedText.isEmpty) {
      return VoiceCommandControllerResult(
        commandResult: result,
        usedAi: false,
        aiConfigured: aiConfigured,
      );
    }

    if (result.recognized || !aiConfigured) {
      return VoiceCommandControllerResult(
        commandResult: result,
        usedAi: false,
        aiConfigured: aiConfigured,
      );
    }

    onAiStarted?.call();
    result = await _aiCommandService.interpretUnknown(text);

    return VoiceCommandControllerResult(
      commandResult: result,
      usedAi: true,
      aiConfigured: aiConfigured,
    );
  }
}
