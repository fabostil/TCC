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

  @override
  State<_TestVoicePage> createState() => _TestVoicePageState();
}

class _TestVoicePageState extends State<_TestVoicePage>
    with ContextualVoiceListeningMixin<_TestVoicePage> {
  int dispatchCount = 0;
  int resumeAttempts = 0;

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

  void processTestCommand() {
    if (!voiceRouteActiveForTesting) {
      return;
    }

    dispatchCount++;
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
        child: ElevatedButton(
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
      ),
    );
  }
}
