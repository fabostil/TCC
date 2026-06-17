import 'dart:async';

import 'package:app_voz/features/voices/coordination/contextual_voice_listening_mixin.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_route_observer.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
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
  Future<void> startContextualVoiceListening() async {
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
          ],
        ),
      ),
    );
  }
}
