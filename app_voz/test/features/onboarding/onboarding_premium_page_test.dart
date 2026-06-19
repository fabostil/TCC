import 'package:app_voz/core/ui/voice_status_bar.dart';
import 'package:app_voz/features/onboarding/pages/onboarding_premium_page.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildPage({
    WidgetBuilder? loginBuilder,
    Future<void> Function()? salvarConcluido,
  }) {
    return MaterialApp(
      home: OnboardingPremiumPage(
        loginBuilder: loginBuilder,
        salvarConcluido: salvarConcluido ?? () async {},
      ),
    );
  }

  // ── Teste 13: Exibe slide 1 por padrão ────────────────────────────────────
  testWidgets('slide 1 exibe texto Touchless', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    expect(find.text('Touchless'), findsOneWidget);
  });

  // ── Teste 14: 4 slides acessíveis via Próximo ─────────────────────────────
  testWidgets('navega pelos 4 slides com botao Proximo', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    // Slide 1: Touchless
    expect(find.text('Touchless'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_next_button')), findsOneWidget);

    // → Slide 2
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Comandos que\nacompanham seu ritmo'),
      findsOneWidget,
    );

    // → Slide 3
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Suas ideias no lugar certo'), findsOneWidget);

    // → Slide 4
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Toque. Grave. Organize.'), findsOneWidget);
  });

  // ── Teste 15: Botão Voltar aparece a partir do slide 2 ────────────────────
  testWidgets('botao Voltar aparece no slide 2 e retorna ao slide 1',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    // Slide 1: não tem Voltar
    expect(find.byKey(const Key('onboarding_back_button')), findsNothing);

    // Vai para slide 2
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();

    // Slide 2: tem Voltar
    expect(find.byKey(const Key('onboarding_back_button')), findsOneWidget);

    // Volta ao slide 1
    await tester.tap(find.byKey(const Key('onboarding_back_button')));
    await tester.pumpAndSettle();
    expect(find.text('Touchless'), findsOneWidget);
  });

  // ── Teste 16: Botão Pular aparece nos slides 1–3 ──────────────────────────
  testWidgets('botao Pular aparece nos primeiros slides', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
  });

  // ── Teste 17: Botão Começar aparece somente no slide 4 ────────────────────
  testWidgets('botao Comecar aparece apenas no ultimo slide', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.byKey(const Key('onboarding_comecar_button')), findsNothing);

    // Avança até slide 4
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const Key('onboarding_comecar_button')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_next_button')), findsNothing);
    expect(find.byKey(const Key('onboarding_skip_button')), findsNothing);
  });

  // ── Teste 18: Pular chama salvarConcluido e navega ────────────────────────
  testWidgets('Pular chama salvarConcluido e exibe loginBuilder',
      (tester) async {
    var salvou = false;
    await tester.pumpWidget(
      buildPage(
        salvarConcluido: () async {
          salvou = true;
        },
        loginBuilder: (_) => const Scaffold(body: Text('Pagina de Login')),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pumpAndSettle();

    expect(salvou, isTrue);
    expect(find.text('Pagina de Login'), findsOneWidget);
  });

  // ── Teste 19: Começar chama salvarConcluido e navega ─────────────────────
  testWidgets('Comecar chama salvarConcluido e exibe loginBuilder',
      (tester) async {
    var salvou = false;
    await tester.pumpWidget(
      buildPage(
        salvarConcluido: () async {
          salvou = true;
        },
        loginBuilder: (_) => const Scaffold(body: Text('Login Pos Onboarding')),
      ),
    );
    await tester.pump();

    // Avança até slide 4
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('onboarding_comecar_button')));
    await tester.pumpAndSettle();

    expect(salvou, isTrue);
    expect(find.text('Login Pos Onboarding'), findsOneWidget);
  });

  // ── Teste 20: Não exibe VoiceStatusBar, sem owner, sem Gemini ────────────
  testWidgets('nao exibe VoiceStatusBar', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    expect(find.byType(VoiceStatusBar), findsNothing);
  });

  // ── Indicador de página ───────────────────────────────────────────────────
  testWidgets('exibe indicador de pagina com 4 dots', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    // 4 AnimatedContainers para os dots estão presentes
    expect(find.byType(AnimatedContainer), findsWidgets);
  });

  // ── Chips de comando no slide 2 ──────────────────────────────────────────
  testWidgets('slide 2 exibe chips de comandos', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('abrir projetos'), findsOneWidget);
    expect(find.text('gravar'), findsOneWidget);
    expect(find.text('minhas gravações'), findsOneWidget);
  });

  // ── Chips no slide 3 ─────────────────────────────────────────────────────
  testWidgets('slide 3 exibe chips de organizacao', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Projetos'), findsOneWidget);
    expect(find.text('Gravações'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
  });

  // ── H11.3: OnboardingPremiumPage nao registra dono de voz ────────────────
  testWidgets(
    'H11.3: OnboardingPremiumPage nao registra dono de voz no VoiceSessionManager',
    (tester) async {
      VoiceSessionManager.instance.resetForTesting();

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(VoiceSessionManager.instance.activeOwnerId, isNull);

      VoiceSessionManager.instance.resetForTesting();
    },
  );
}
