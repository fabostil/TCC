import 'package:app_voz/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renderiza tela inicial do assistente', (tester) async {
    await tester.pumpWidget(const AppVoz());

    expect(find.text('Assistente de Voz para Músicos'), findsOneWidget);
    expect(find.textContaining('Comandos suportados'), findsOneWidget);
  });
}
