import 'package:app_voz/features/editor/pages/editor_page.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorVoiceFlowPolicy', () {
    const policy = EditorVoiceFlowPolicy();

    test('permite comandos globais quando nao ha gravacao ativa', () {
      expect(
        policy.navigationDecision(
          recording: false,
          commandType: VoiceCommandType.abrirConfiguracoes,
        ),
        EditorVoiceNavigationDecision.allow,
      );
      expect(
        policy.navigationDecision(
          recording: false,
          commandType: VoiceCommandType.voltar,
        ),
        EditorVoiceNavigationDecision.allow,
      );
    });

    test('bloqueia navegacao global durante gravacao ativa', () {
      expect(
        policy.navigationDecision(
          recording: true,
          commandType: VoiceCommandType.abrirConfiguracoes,
        ),
        EditorVoiceNavigationDecision.block,
      );
      expect(
        policy.recordingNavigationBlockedMessage,
        'Há uma gravação em andamento. Encerre ou cancele antes de sair.',
      );
    });

    test('exige confirmacao para voltar ou sair durante gravacao ativa', () {
      expect(
        policy.navigationDecision(
          recording: true,
          commandType: VoiceCommandType.voltar,
        ),
        EditorVoiceNavigationDecision.confirmExit,
      );
      expect(
        policy.navigationDecision(
          recording: true,
          commandType: VoiceCommandType.sair,
        ),
        EditorVoiceNavigationDecision.confirmExit,
      );
    });

    test('documenta mensagem de indisponibilidade de voz durante gravacao', () {
      expect(
        policy.recordingVoiceUnavailableMessage,
        'Gravação em andamento. Use os controles da tela para pausar ou encerrar.',
      );
    });
  });
}
