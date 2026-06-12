import 'package:app_voz/core/ui/app_empty_state.dart';
import 'package:app_voz/core/ui/app_feedback.dart';
import 'package:app_voz/core/ui/app_loading_view.dart';
import 'package:app_voz/core/ui/app_search_field.dart';
import 'package:app_voz/core/ui/user_facing_messages.dart';
import 'package:app_voz/core/ui/voice_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSearchField', () {
    testWidgets('chama onChanged e exibe botao de limpar quando ha texto', (
      tester,
    ) async {
      final controller = TextEditingController();
      String? changedValue;
      var cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSearchField(
              controller: controller,
              hintText: 'Buscar',
              onChanged: (value) => changedValue = value,
              onClear: () {
                cleared = true;
                controller.clear();
              },
            ),
          ),
        ),
      );

      expect(find.byTooltip('Limpar busca'), findsNothing);

      await tester.enterText(find.byType(TextField), 'demo');
      await tester.pump();

      expect(changedValue, 'demo');
      expect(find.byTooltip('Limpar busca'), findsOneWidget);

      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pump();

      expect(cleared, isTrue);
      expect(controller.text, isEmpty);
      expect(find.byTooltip('Limpar busca'), findsNothing);
    });

    testWidgets('desabilita campo quando enabled e falso', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSearchField(
              controller: controller,
              hintText: 'Buscar',
              onChanged: (_) {},
              onClear: () {},
              enabled: false,
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });

  group('VoiceStatusBar', () {
    testWidgets('mostra icone de microfone quando esta ouvindo', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceStatusBar(message: 'Ouvindo...', listening: true),
          ),
        ),
      );

      expect(find.text('Ouvindo...'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('mostra progresso quando IA esta pensando', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceStatusBar(
              message: 'IA pensando...',
              listening: false,
              thinking: true,
            ),
          ),
        ),
      );

      expect(find.text('IA pensando...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    });

    testWidgets('traduz estado interno para texto amigavel', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceStatusBar(message: 'listeningCommand', listening: true),
          ),
        ),
      );

      expect(find.text('Ouvindo comando'), findsOneWidget);
      expect(find.text('listeningCommand'), findsNothing);
    });

    test('mapeia estados internos para mensagens com acentuacao correta', () {
      expect(UserFacingMessages.voiceStatus('sleeping'), 'Aguardando comando');
      expect(
        UserFacingMessages.voiceStatus('listeningCommand'),
        'Ouvindo comando',
      );
      expect(
        UserFacingMessages.voiceStatus('processing'),
        'Processando comando',
      );
      expect(
        UserFacingMessages.voiceStatus('error'),
        'Não consegui concluir essa ação. Tente novamente.',
      );
    });
  });

  group('UserFacingMessages', () {
    test('remove detalhes tecnicos de erros publicos', () {
      expect(
        UserFacingMessages.error(Exception('GEMINI_API_KEY ausente')),
        UserFacingMessages.genericActionError,
      );
      expect(
        UserFacingMessages.error(
          Exception('PlatformException(sign_in_failed)'),
        ),
        UserFacingMessages.genericActionError,
      );
    });

    test('preserva mensagem amigavel de validacao', () {
      expect(
        UserFacingMessages.error(ArgumentError('Informe uma frase válida.')),
        'Informe uma frase válida.',
      );
    });

    test('mensagens compartilhadas sao especificas e sem termos tecnicos', () {
      const messages = [
        UserFacingMessages.genericActionError,
        UserFacingMessages.commandExecutionError,
        UserFacingMessages.dataLoadError,
        UserFacingMessages.dataSaveError,
        UserFacingMessages.playbackError,
        UserFacingMessages.recordingControlError,
        UserFacingMessages.recordingSaveError,
      ];

      for (final message in messages) {
        final lower = message.toLowerCase();
        expect(lower, isNot(contains('exception')));
        expect(lower, isNot(contains('stacktrace')));
        expect(lower, isNot(contains('sqlite')));
        expect(lower, isNot(contains('hash')));
        expect(lower, isNot(contains('token')));
      }

      expect(
        UserFacingMessages.playbackError,
        contains('Verifique se o arquivo está disponível'),
      );
      expect(
        UserFacingMessages.recordingControlError,
        contains('Verifique o microfone'),
      );
    });

    test('mostra somente nome do arquivo em caminho interno', () {
      expect(
        UserFacingMessages.currentRecordingFile(
          r'C:\Users\aleli\AppData\audio\take-01.m4a',
        ),
        'Arquivo atual: take-01.m4a',
      );
      expect(
        UserFacingMessages.currentRecordingFile(
          '/data/user/0/br.com.app/files/take-02.wav',
        ),
        'Arquivo atual: take-02.wav',
      );
    });
  });

  group('Estados compartilhados', () {
    testWidgets('AppEmptyState renderiza estado vazio informativo', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.folder_off,
              title: 'Nenhum projeto',
              subtitle: 'Crie um projeto para começar.',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.folder_off), findsOneWidget);
      expect(find.text('Nenhum projeto'), findsOneWidget);
      expect(find.text('Crie um projeto para começar.'), findsOneWidget);
    });

    testWidgets('AppLoadingView renderiza mensagem de carregamento', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppLoadingView(message: 'Carregando projetos')),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Carregando projetos'), findsOneWidget);
    });
  });

  group('AppFeedback', () {
    testWidgets('confirm retorna false ao cancelar e true ao confirmar', (
      tester,
    ) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                testContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final cancelResult = AppFeedback.confirm(
        testContext,
        title: 'Excluir',
        message: 'Deseja excluir?',
        destructive: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('Excluir'), findsOneWidget);
      expect(find.text('Deseja excluir?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();
      expect(await cancelResult, isFalse);

      final confirmResult = AppFeedback.confirm(
        testContext,
        title: 'Excluir',
        message: 'Deseja excluir?',
        destructive: true,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(await confirmResult, isTrue);
    });
  });
}
