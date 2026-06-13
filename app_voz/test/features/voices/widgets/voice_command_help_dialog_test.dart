import 'package:app_voz/features/voices/widgets/voice_command_help_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renderiza categorias e comandos principais sem termos tecnicos',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VoiceCommandHelpDialog())),
      );

      expect(find.text('Comandos de voz'), findsOneWidget);
      expect(find.text('Navegação'), findsOneWidget);
      expect(find.text('Gravação'), findsOneWidget);
      expect(find.text('Reprodução'), findsOneWidget);
      expect(find.text('Listas'), findsOneWidget);
      expect(find.text('Confirmações'), findsOneWidget);
      expect(find.text('Meus projetos'), findsOneWidget);
      expect(find.text('Gravar'), findsOneWidget);
      expect(find.text('Descer'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(
        find.text(
          'Você também pode criar comandos personalizados em Configurações.',
        ),
        findsOneWidget,
      );

      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .join(' ')
          .toLowerCase();

      expect(allText, isNot(contains('gemini')));
      expect(allText, isNot(contains('nlu')));
      expect(allText, isNot(contains('commandservice')));
      expect(allText, isNot(contains('api')));
      expect(allText, isNot(contains('parser')));
    },
  );
}
