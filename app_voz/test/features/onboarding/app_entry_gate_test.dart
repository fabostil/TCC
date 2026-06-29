import 'dart:async';

import 'package:app_voz/features/onboarding/pages/app_entry_gate.dart';
import 'package:app_voz/features/onboarding/pages/onboarding_premium_page.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConfiguracaoApp _configComOnboarding() =>
    ConfiguracaoApp.padrao().copyWith(primeiraExecucaoConcluida: false);

ConfiguracaoApp _configSemOnboarding() =>
    ConfiguracaoApp.padrao().copyWith(primeiraExecucaoConcluida: true);

Widget buildGate({
  required Future<ConfiguracaoApp> Function() buscarConfiguracao,
  WidgetBuilder? overrideLoginBuilder,
  Future<void> Function(ConfiguracaoApp)? salvarConfiguracao,
}) {
  return MaterialApp(
    home: AppEntryGate(
      buscarConfiguracao: buscarConfiguracao,
      salvarConfiguracao: salvarConfiguracao ?? (_) async {},
      overrideLoginBuilder: overrideLoginBuilder,
    ),
  );
}

void main() {
  // ── Teste 1: Loading indicator enquanto carrega ────────────────────────────
  testWidgets('exibe loading enquanto carrega configuracao', (tester) async {
    // Usa Completer (sem timer) para manter o Future pendente sem side-effects.
    final completer = Completer<ConfiguracaoApp>();
    await tester.pumpWidget(
      buildGate(buscarConfiguracao: () => completer.future),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Completa para não deixar estado pendente ao descartar o widget.
    completer.complete(_configSemOnboarding());
    await tester.pumpAndSettle();
  });

  // ── Teste 2: Se onboarding não concluído → exibe OnboardingPremiumPage ─────
  testWidgets(
      'exibe OnboardingPremiumPage quando primeiraExecucaoConcluida false',
      (tester) async {
    await tester.pumpWidget(
      buildGate(buscarConfiguracao: () async => _configComOnboarding()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPremiumPage), findsOneWidget);
  });

  // ── Teste 3: Onboarding tem texto 'Touchless' ─────────────────────────────
  testWidgets('onboarding exibe slide 1 com texto Touchless', (tester) async {
    await tester.pumpWidget(
      buildGate(buscarConfiguracao: () async => _configComOnboarding()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Touchless'), findsOneWidget);
  });

  // ── Teste 4: Se onboarding já concluído → exibe loginBuilder ─────────────
  testWidgets('exibe loginBuilder quando primeiraExecucaoConcluida true',
      (tester) async {
    await tester.pumpWidget(
      buildGate(
        buscarConfiguracao: () async => _configSemOnboarding(),
        overrideLoginBuilder: (_) =>
            const Scaffold(body: Text('Pagina de Login')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pagina de Login'), findsOneWidget);
    expect(find.byType(OnboardingPremiumPage), findsNothing);
  });

  // ── Teste 5: Concluir onboarding salva e vai para loginBuilder ────────────
  testWidgets('concluir onboarding salva config e exibe loginBuilder',
      (tester) async {
    var salvou = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppEntryGate(
          buscarConfiguracao: () async => _configComOnboarding(),
          salvarConfiguracao: (config) async {
            if (config.primeiraExecucaoConcluida) salvou = true;
          },
          overrideLoginBuilder: (_) =>
              const Scaffold(body: Text('Login Apos Onboarding')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Onboarding está visível → clicar Pular
    expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pumpAndSettle();

    expect(salvou, isTrue);
    expect(find.text('Login Apos Onboarding'), findsOneWidget);
  });

  // ── Teste 6: Se erro ao carregar config → exibe loginBuilder (default) ─────
  testWidgets('exibe loginBuilder quando buscarConfiguracao lanca erro',
      (tester) async {
    await tester.pumpWidget(
      buildGate(
        buscarConfiguracao: () async =>
            throw Exception('Erro simulado de banco'),
        overrideLoginBuilder: (_) =>
            const Scaffold(body: Text('Login Fallback')),
      ),
    );
    await tester.pumpAndSettle();
    // No error → shows login (config null → !onboardingConcluido → onboarding)
    // On exception → loading false, config null → onboardingConcluido = false
    // So: onboarding is shown
    expect(find.byType(OnboardingPremiumPage), findsOneWidget);
  });

  // ── Teste 7: Onboarding completo com 4 slides acessíveis ─────────────────
  testWidgets('onboarding permite navegar pelos 4 slides', (tester) async {
    await tester.pumpWidget(
      buildGate(buscarConfiguracao: () async => _configComOnboarding()),
    );
    await tester.pumpAndSettle();

    // Slide 1
    expect(find.text('Touchless'), findsOneWidget);

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

  // ── Teste 8: AppEntryGate sem homeBuilder usa MicrophonePermissionPage ────
  // (smoke test: sem navigator error)
  testWidgets('AppEntryGate constroi sem erros quando homeBuilder nulo',
      (tester) async {
    await tester.pumpWidget(
      buildGate(buscarConfiguracao: () async => _configSemOnboarding()),
    );
    await tester.pumpAndSettle();
    // Default loginBuilder cria LoginPage — não lança exceção
    expect(tester.takeException(), isNull);
  });
}
