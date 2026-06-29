import 'package:app_voz/features/voices/widgets/google_sign_in_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('executa callback quando nao esta carregando', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoogleSignInButton(
            loading: false,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Entrar com Google'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    expect(pressed, isTrue);
  });

  testWidgets('desabilita botao e mostra loading', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoogleSignInButton(
            loading: true,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Entrando com Google...'), findsOneWidget);
    expect(find.text('Entrar com Google'), findsNothing);
    expect(find.byIcon(Icons.verified_user_outlined), findsNothing);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    expect(pressed, isFalse);
  });
}
