import 'package:app_voz/features/voices/widgets/voice_command_help_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'contexto geral renderiza categorias principais sem termos tecnicos',
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
        find.textContaining('Você também pode criar comandos personalizados'),
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

  testWidgets('contexto Home renderiza comandos de navegacao', (tester) async {
    await _pumpHelp(tester, const VoiceCommandHelpDialog.forHome());

    expect(find.text('Comandos de voz'), findsOneWidget);
    expect(find.text('Navegação'), findsOneWidget);
    expect(find.text('Meus projetos'), findsOneWidget);
    expect(find.text('Minhas gravações'), findsOneWidget);
    expect(find.text('Tela inicial'), findsOneWidget);
    _expectNoTechnicalTerms(tester);
  });

  testWidgets('contexto Projetos renderiza comandos de projeto e lista', (
    tester,
  ) async {
    await _pumpHelp(tester, const VoiceCommandHelpDialog.forProjects());

    expect(find.text('Comandos em projetos'), findsOneWidget);
    expect(find.text('Novo projeto'), findsOneWidget);
    expect(find.text('Criar projeto'), findsOneWidget);
    expect(find.text('Descer'), findsOneWidget);
    expect(find.text('Ir para o fim'), findsOneWidget);
    _expectNoTechnicalTerms(tester);
  });

  testWidgets('contexto Gravacoes renderiza reproducao e exclusao', (
    tester,
  ) async {
    await _pumpHelp(tester, const VoiceCommandHelpDialog.forRecordings());

    expect(find.text('Comandos em gravações'), findsOneWidget);
    expect(find.text('Tocar'), findsOneWidget);
    expect(find.text('Dar play'), findsOneWidget);
    expect(find.text('Excluir gravação'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
    _expectNoTechnicalTerms(tester);
  });

  testWidgets('contexto Editor renderiza gravacao e aviso sobre microfone', (
    tester,
  ) async {
    await _pumpHelp(tester, const VoiceCommandHelpDialog.forEditor());

    expect(find.text('Comandos no editor'), findsOneWidget);
    expect(find.text('Gravar'), findsOneWidget);
    expect(find.text('Finalizar gravação'), findsOneWidget);
    expect(find.text('Parar reprodução'), findsOneWidget);
    expect(find.textContaining('microfone está sendo usado'), findsOneWidget);
    _expectNoTechnicalTerms(tester);
  });

  testWidgets('contexto Configuracoes renderiza tema e controle por voz', (
    tester,
  ) async {
    await _pumpHelp(tester, const VoiceCommandHelpDialog.forSettings());

    expect(find.text('Comandos em configurações'), findsOneWidget);
    expect(find.text('Controle por voz'), findsOneWidget);
    expect(find.text('Ativar controle por voz'), findsOneWidget);
    expect(find.text('Modo escuro'), findsOneWidget);
    expect(find.text('Tema claro'), findsOneWidget);
    _expectNoTechnicalTerms(tester);
  });
}

Future<void> _pumpHelp(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void _expectNoTechnicalTerms(WidgetTester tester) {
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
}
