import 'package:app_voz/features/voices/pages/cadastro_page.dart';
import 'package:app_voz/features/voices/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LoginPage valida campos obrigatorios antes de autenticar', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Digite sua senha para continuar.'), findsOneWidget);
  });

  testWidgets('LoginPage alterna visibilidade da senha', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    TextField passwordField = tester.widget(
      find.descendant(
        of: find.byType(TextFormField).at(1),
        matching: find.byType(TextField),
      ),
    );
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    passwordField = tester.widget(
      find.descendant(
        of: find.byType(TextFormField).at(1),
        matching: find.byType(TextField),
      ),
    );
    expect(passwordField.obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('CadastroPage valida dados locais antes de cadastrar', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CadastroPage()));

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Cadastrar com e-mail'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Cadastrar com e-mail'),
    );
    await tester.pump();

    expect(find.text('Informe seu nome.'), findsOneWidget);
    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(
      find.text('Crie uma senha para proteger sua conta.'),
      findsOneWidget,
    );
    expect(find.text('Confirme sua senha.'), findsOneWidget);
  });

  testWidgets('CadastroPage valida confirmacao de senha', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CadastroPage()));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Ana Silva',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'ana@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'Senha123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar senha'),
      'Senha124',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Cadastrar com e-mail'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Cadastrar com e-mail'),
    );
    await tester.pump();

    expect(find.text('As senhas não conferem.'), findsOneWidget);
  });
}
