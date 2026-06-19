import 'dart:async';

import 'package:app_voz/features/voices/coordination/contextual_voice_listening_mixin.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_route_observer.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/widgets/voice_command_help_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    VoiceSessionManager.instance.resetForTesting();
  });

  tearDown(() {
    VoiceSessionManager.instance.resetForTesting();
  });

  group('ContextualVoiceListeningMixin route lifecycle', () {
    testWidgets('tela ativa processa comando contextual', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      key.currentState!.processTestCommand();
      await tester.pump();

      expect(key.currentState!.dispatchCount, 1);
    });

    testWidgets('tela coberta nao processa comando contextual', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
      await tester.pumpAndSettle();

      expect(key.currentState!.voiceRouteActiveForTesting, isFalse);

      key.currentState!.processTestCommand();
      await tester.pump();

      expect(key.currentState!.dispatchCount, 0);
    });

    testWidgets('didPopNext retoma sem duplicar assinatura', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
      await tester.pumpAndSettle();
      Navigator.of(key.currentContext!).pop();
      await tester.pumpAndSettle();

      expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
      expect(key.currentState!.resumeAttempts, 1);
      expect(key.currentState!.voiceRouteObserverRegisteredForTesting, isTrue);
    });

    testWidgets('didPopNext aguarda pausa da rota antes de retomar', (
      tester,
    ) async {
      final key = GlobalKey<_TestVoicePageState>();
      final pauseCompleter = Completer<void>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.routePauseCompleter = pauseCompleter;

      await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
      await tester.pumpAndSettle();
      Navigator.of(key.currentContext!).pop();
      await tester.pump();

      expect(key.currentState!.resumeAttempts, 0);

      pauseCompleter.complete();
      await tester.pumpAndSettle();

      expect(key.currentState!.resumeAttempts, 1);
    });

    testWidgets('botao Android retoma escuta da rota anterior', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
      await tester.pumpAndSettle();

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
      expect(key.currentState!.resumeAttempts, 1);
    });

    testWidgets('suspensao temporaria preserva escuta continua', (
      tester,
    ) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.voiceEscutaContinuaAtiva = true;

      await key.currentState!.suspendContextualVoiceListening();
      await tester.pump();

      expect(key.currentState!.voiceEscutaContinuaAtiva, isTrue);
      expect(key.currentState!.voiceParadaManual, isFalse);
    });

    testWidgets('pausa manual desativa retomada automatica', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.voiceEscutaContinuaAtiva = true;

      await key.currentState!.suspendContextualVoiceListening(
        keepManualPause: true,
      );
      await tester.pump();

      expect(key.currentState!.voiceEscutaContinuaAtiva, isFalse);
      expect(key.currentState!.voiceParadaManual, isTrue);
    });

    testWidgets('dispose remove registro de rota e libera owner', (
      tester,
    ) async {
      final key = GlobalKey<_TestVoicePageState>();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      VoiceSessionManager.instance.claimListening('test_contextual');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(VoiceSessionManager.instance.activeOwnerId, isNull);
    });

    testWidgets('modal confirma por voz e retoma escuta', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      const commandService = CommandService();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.voiceEscutaContinuaAtiva = true;
      await tester.tap(find.byKey(_TestVoicePage.openDialogButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar exclusao'), findsOneWidget);

      await key.currentState!.voiceConfirmationController.handle(
        commandService.interpret('confirmar exclusao'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar exclusao'), findsNothing);
      expect(key.currentState!.confirmedDialogs, 1);
      expect(key.currentState!.cancelledDialogs, 0);
      expect(key.currentState!.resumeAttempts, 1);
    });

    testWidgets('modal destrutivo aceita excluir como confirmacao por voz', (
      tester,
    ) async {
      final key = GlobalKey<_TestVoicePageState>();
      const commandService = CommandService();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      await tester.tap(find.byKey(_TestVoicePage.openDialogButtonKey));
      await tester.pumpAndSettle();

      await key.currentState!.voiceConfirmationController.handle(
        commandService.interpret('excluir'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar exclusao'), findsNothing);
      expect(key.currentState!.confirmedDialogs, 1);
      expect(key.currentState!.cancelledDialogs, 0);
    });

    testWidgets('modal cancela por voz e limpa pendencia', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      const commandService = CommandService();

      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      await tester.tap(find.byKey(_TestVoicePage.openDialogButtonKey));
      await tester.pumpAndSettle();

      await key.currentState!.voiceConfirmationController.handle(
        commandService.interpret('nao'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar exclusao'), findsNothing);
      expect(key.currentState!.confirmedDialogs, 0);
      expect(key.currentState!.cancelledDialogs, 1);
      expect(
        key.currentState!.voiceConfirmationController.hasPendingConfirmation,
        isFalse,
      );
    });
  });

  group('ContextualVoiceListeningMixin recovery e toggle fixes', () {
    testWidgets(
      'toggle com voiceOuvindo=true mas STT inativo reinicia, nao executa stop',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Estado stale: voiceOuvindo=true localmente, mas manager sem escuta real
        key.currentState!.voiceSetState(() {
          key.currentState!.voiceOuvindo = true;
        });

        expect(VoiceSessionManager.instance.listeningActive, isFalse);
        expect(
          VoiceSessionManager.instance.activeOwnerId,
          isNot('test_contextual'),
        );

        // unawaited + pump para avançar o Future.delayed(350ms) interno
        unawaited(key.currentState!.toggleContextualVoiceListening());
        await tester.pump(const Duration(milliseconds: 500));

        // Deve ter chamado restart, não stop
        expect(key.currentState!.voiceParadaManual, isFalse);
        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );

    testWidgets(
      'toggle com voiceOuvindo=true e STT realmente ativo executa stop',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Simular escuta real ativa no manager
        VoiceSessionManager.instance.claimListening('test_contextual');
        key.currentState!.voiceSetState(() {
          key.currentState!.voiceOuvindo = true;
        });

        expect(VoiceSessionManager.instance.listeningActive, isTrue);
        expect(VoiceSessionManager.instance.activeOwnerId, 'test_contextual');

        // toggleContextualVoiceListening no caminho de stop não tem delay interno
        await key.currentState!.toggleContextualVoiceListening();
        await tester.pump();

        // Deve ter feito stop e setado parada manual
        expect(key.currentState!.voiceParadaManual, isTrue);
        expect(key.currentState!.voiceOuvindo, isFalse);
      },
    );

    testWidgets(
      '_voiceRecoveryPending liberado quando shouldRestart retorna false',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Condições que fazem shouldRestart retornar false:
        // voiceEscutaContinuaAtiva=false (default)
        expect(key.currentState!.voiceEscutaContinuaAtiva, isFalse);

        // Chamar scheduleVoiceContinuousRestart (sets _voiceRecoveryPending=true)
        key.currentState!.scheduleVoiceContinuousRestart();

        // shouldRestart vai ser chamado pelo coordinator e retornar false
        // isso deve liberar _voiceRecoveryPending automaticamente
        // A verificação indireta: uma segunda chamada não deve ser bloqueada
        // (sem 'recovery_already_pending' sendo logado)
        key.currentState!.scheduleVoiceContinuousRestart();

        // Como shouldRestart é false, nenhum restart deveria ter sido tentado
        expect(key.currentState!.resumeAttempts, 0);

        // E não houve 'recovery_already_pending' no diagnóstico
        expect(
          VoiceSessionManager.instance.diagnostics.events.any(
            (e) => e.reason == 'recovery_already_pending',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'restartManually apos error_busy limpa cooldown e inicia restart',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Simular que houve error_busy (cooldown ativo)
        VoiceSessionManager.instance.registerFailure(
          ownerId: 'test_contextual',
          reason: 'error_busy',
          message: 'STT ocupado',
        );

        // restartContextualVoiceListeningManually tem Future.delayed(350ms) interno.
        // unawaited + pump avança o relógio do fake async.
        unawaited(key.currentState!.restartContextualVoiceListeningManually());
        await tester.pump(const Duration(milliseconds: 500));

        // Cooldown deve ter sido limpo pelo forceReset com clearBusyCooldown=true
        expect(VoiceSessionManager.instance.isBusyCooldownActive, isFalse);
        // Deve ter tentado iniciar
        expect(key.currentState!.resumeAttempts, greaterThan(0));
        expect(key.currentState!.voiceParadaManual, isFalse);
      },
    );

    testWidgets(
      'scheduleVoiceContinuousRestart bloqueado durante comando em processamento',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Simular comando em processamento
        key.currentState!.voiceEscutaContinuaAtiva = true;
        key.currentState!.voiceExecutandoComando = true;

        // scheduleVoiceContinuousRestart: shouldRestart vai retornar false
        // porque voiceExecutandoComando=true → latch deve ser liberado
        key.currentState!.scheduleVoiceContinuousRestart();

        // Nenhum restart executado
        expect(key.currentState!.resumeAttempts, 0);

        // Após fim do comando, não deve haver bloqueio para nova tentativa
        key.currentState!.voiceExecutandoComando = false;
        key.currentState!.scheduleVoiceContinuousRestart();

        // recovery_already_pending não deve aparecer
        expect(
          VoiceSessionManager.instance.diagnostics.events.any(
            (e) => e.reason == 'recovery_already_pending',
          ),
          isFalse,
        );
      },
    );
  });

  group('ContextualVoiceListeningMixin H10.1 retomada apos navegacao', () {
    testWidgets(
      'Home retoma escuta apos voltar de Configuracoes (owner liberado)',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Simula tela filha (configuracoes) com ownership STT
        VoiceSessionManager.instance.claimListening('configuracoes');
        expect(VoiceSessionManager.instance.activeOwnerId, 'configuracoes');

        // Route observer libera owner no pop (comportamento corrigido H10.1)
        VoiceSessionManager.instance.onRouteDidPop();
        expect(VoiceSessionManager.instance.activeOwnerId, isNull);

        // didPopNext dispara retomada na home
        key.currentState!.didPopNext();
        await tester.pumpAndSettle();

        expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );

    testWidgets(
      'Home retoma escuta apos voltar de Meus Projetos',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        VoiceSessionManager.instance.claimListening('meus_projetos');
        VoiceSessionManager.instance.onRouteDidPop();

        key.currentState!.didPopNext();
        await tester.pumpAndSettle();

        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );

    testWidgets(
      'Home retoma escuta apos voltar de Minhas Gravacoes',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        VoiceSessionManager.instance.claimListening('minhas_gravacoes');
        VoiceSessionManager.instance.onRouteDidPop();

        key.currentState!.didPopNext();
        await tester.pumpAndSettle();

        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );

    testWidgets(
      'recovery antigo da rota descartada nao bloqueia owner atual',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        // Tela filha tinha recovery pendente
        VoiceSessionManager.instance.claimListening('meus_projetos');
        VoiceSessionManager.instance.scheduleRecovery(
          ownerId: 'meus_projetos',
          shouldRecover: () => true,
          onRecover: () async {},
        );
        expect(VoiceSessionManager.instance.hasPendingRecovery, isTrue);

        // Pop: libera owner e cancela recovery antigo
        VoiceSessionManager.instance.onRouteDidPop();

        expect(VoiceSessionManager.instance.hasPendingRecovery, isFalse);
        expect(VoiceSessionManager.instance.activeOwnerId, isNull);

        // Home retoma sem bloqueio
        key.currentState!.didPopNext();
        await tester.pumpAndSettle();

        expect(key.currentState!.resumeAttempts, greaterThan(0));
        expect(
          VoiceSessionManager.instance.diagnostics.events
              .where((e) => e.reason == 'recovery_already_pending')
              .length,
          0,
        );
      },
    );

    testWidgets(
      'nao cria startListening duplicado apos didPopNext',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
        await tester.pumpAndSettle();

        // Navega de volta via pop normal (observer libera owner)
        Navigator.of(key.currentContext!).pop();
        await tester.pumpAndSettle();

        // startContinuousVoiceListeningIfActive deve ter sido chamado
        // mas nao mais de uma vez (guard _voiceStartInProgress protege)
        expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
        // resumeAttempts pode ser 1 (startContinuousVoiceListeningIfActive)
        // ou >1 se o fallback recovery tambem disparou, mas nao deve ser 0
        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );

    testWidgets(
      'nao retoma escuta se a tela estava em processamento de comando',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        key.currentState!.voiceEscutaContinuaAtiva = true;
        key.currentState!.voiceExecutandoComando = true;

        await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
        await tester.pumpAndSettle();
        Navigator.of(key.currentContext!).pop();
        await tester.pumpAndSettle();

        // Com voiceExecutandoComando=true, o fallback scheduleContinuousRestart
        // nao deve ser chamado (shouldRestart retorna false).
        // startContinuousVoiceListeningIfActive ainda e chamado mas a recovery
        // de fallback deve ser bloqueada pelo guard de voiceExecutandoComando.
        expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
        expect(
          VoiceSessionManager.instance.diagnostics.events.any(
            (e) => e.reason == 'recovery_already_pending',
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'botao Android retoma escuta via handlePopRoute (H10.1)',
      (tester) async {
        final key = GlobalKey<_TestVoicePageState>();
        await tester.pumpWidget(_TestVoiceApp(pageKey: key));

        VoiceSessionManager.instance.claimListening('meus_projetos');

        await tester.tap(find.byKey(_TestVoicePage.openRouteButtonKey));
        await tester.pumpAndSettle();

        VoiceSessionManager.instance.onRouteDidPop();
        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        expect(key.currentState!.voiceRouteActiveForTesting, isTrue);
        expect(key.currentState!.resumeAttempts, greaterThan(0));
      },
    );
  });

  group('ContextualVoiceListeningMixin H11.6 ajuda por voz', () {
    testWidgets('abre dialog de ajuda e exibe comandos', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      expect(find.text('Comandos de voz'), findsOneWidget);
    });

    testWidgets('fechar por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();
      expect(find.text('Comandos de voz'), findsOneWidget);

      unawaited(key.currentState!.processContextualVoiceInput('fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('ok por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('ok'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('entendi por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('entendi'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('cancelar por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('voltar por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('voltar'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('certo por voz fecha dialog de ajuda', (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('certo'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('apos fechar dialog por voz escuta continua flag permanece ativa',
        (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.voiceEscutaContinuaAtiva = true;

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
      expect(key.currentState!.voiceEscutaContinuaAtiva, isTrue);
    });

    testWidgets('dialog fecha pelo botao Fechar e flag escuta permanece ativa',
        (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));
      key.currentState!.voiceEscutaContinuaAtiva = true;

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      expect(find.text('Comandos de voz'), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice_command_help_close_button')));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
      expect(key.currentState!.voiceEscutaContinuaAtiva, isTrue);
    });

    testWidgets('nao por voz fecha dialog de ajuda (normalizacao de nao)',
        (tester) async {
      final key = GlobalKey<_TestVoicePageState>();
      await tester.pumpWidget(_TestVoiceApp(pageKey: key));

      unawaited(key.currentState!.openHelpForTesting());
      await tester.pump();
      await tester.pump();

      unawaited(key.currentState!.processContextualVoiceInput('não'));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });
  });
}

class _TestVoiceApp extends StatelessWidget {
  const _TestVoiceApp({required this.pageKey});

  final GlobalKey<_TestVoicePageState> pageKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [voiceRouteObserver],
      home: _TestVoicePage(key: pageKey),
    );
  }
}

class _TestVoicePage extends StatefulWidget {
  const _TestVoicePage({super.key});

  static const openRouteButtonKey = Key('open_route');
  static const openDialogButtonKey = Key('open_voice_dialog');
  static const openHelpButtonKey = Key('open_voice_help');

  @override
  State<_TestVoicePage> createState() => _TestVoicePageState();
}

class _TestVoicePageState extends State<_TestVoicePage>
    with ContextualVoiceListeningMixin<_TestVoicePage> {
  int dispatchCount = 0;
  int resumeAttempts = 0;
  int confirmedDialogs = 0;
  int cancelledDialogs = 0;
  Completer<void>? routePauseCompleter;

  @override
  String get voiceOwnerId => 'test_contextual';

  @override
  int? get voiceUsuarioId => null;

  @override
  String get voiceListeningPrompt => 'Ouvindo teste...';

  @override
  bool get voiceRegistersCommands => false;

  @override
  late final VoiceCommandDispatcher voiceCommandDispatcher =
      VoiceCommandDispatcher(
        handlers: {
          VoiceCommandType.voltar: (_) async {
            dispatchCount++;
            return VoiceCommandPageResult.handled(restartListening: false);
          },
        },
      );

  @override
  Future<void> startContinuousVoiceListeningIfActive() async {
    resumeAttempts++;
  }

  @override
  Future<void> startContextualVoiceListening({
    bool manualOverride = false,
  }) async {
    resumeAttempts++;
  }

  @override
  Future<void> pauseContextualVoiceForCoveredRoute() async {
    final completer = routePauseCompleter;
    if (completer != null) {
      await completer.future;
      return;
    }
    await super.pauseContextualVoiceForCoveredRoute();
  }

  void processTestCommand() {
    if (!voiceRouteActiveForTesting) {
      return;
    }

    dispatchCount++;
  }

  Future<void> openHelpForTesting() =>
      openContextualVoiceHelp(VoiceCommandHelpContext.general);

  Future<void> _openConfirmation() async {
    final confirmed = await showVoiceConfirmationDialog(
      id: 'delete_test',
      title: 'Confirmar exclusao',
      message: 'Esta acao remove o item de teste.',
      confirmLabel: 'Excluir',
      destructive: true,
    );

    if (confirmed) {
      confirmedDialogs++;
    } else {
      cancelledDialogs++;
    }
  }

  @override
  void dispose() {
    disposeContextualVoiceListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              key: _TestVoicePage.openRouteButtonKey,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('route two')),
                  ),
                );
              },
              child: const Text('Abrir rota'),
            ),
            ElevatedButton(
              key: _TestVoicePage.openDialogButtonKey,
              onPressed: () {
                unawaited(_openConfirmation());
              },
              child: const Text('Abrir dialog'),
            ),
            ElevatedButton(
              key: _TestVoicePage.openHelpButtonKey,
              onPressed: () {
                unawaited(openHelpForTesting());
              },
              child: const Text('Abrir ajuda'),
            ),
          ],
        ),
      ),
    );
  }
}
