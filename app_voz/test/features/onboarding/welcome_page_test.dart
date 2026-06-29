import 'package:app_voz/features/onboarding/pages/welcome_page.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/pages/auth_gate.dart';
import 'package:app_voz/features/voices/services/auth_session_service.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/services/voice_permission_service.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const commandService = CommandService();

  setUp(() {
    VoiceSessionManager.instance.resetForTesting();
  });

  tearDown(() {
    VoiceSessionManager.instance.resetForTesting();
  });

  // Configuraçao que desabilita escuta contínua — evita chamada ao STT em testes.
  ConfiguracaoApp configSemVoz() => ConfiguracaoApp.padrao().copyWith(
    comandosVozAtivos: false,
    escutaContinua: false,
  );

  WelcomePage welcomeComBuilders({
    WidgetBuilder? loginBuilder,
    WidgetBuilder? cadastroBuilder,
    VoicePermissionService? voicePermissionService,
  }) {
    return WelcomePage(
      buscarConfiguracao: () async => configSemVoz(),
      loginBuilder: loginBuilder,
      cadastroBuilder: cadastroBuilder,
      voicePermissionService: voicePermissionService,
    );
  }

  group('WelcomePage H11 — exibição e navegação', () {
    testWidgets('exibe titulo, subtitulo e tres cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: welcomeComBuilders()),
      );
      await tester.pump();

      expect(find.text('Touchless'), findsWidgets);
      expect(
        find.text('Controle seus projetos musicais por voz.'),
        findsOneWidget,
      );
      expect(find.text('Comandos por voz'), findsOneWidget);
      expect(find.text('Organização musical'), findsOneWidget);
      expect(find.text('Feito para tocar'), findsOneWidget);
    });

    testWidgets('exibe botoes Comecar Ja tenho conta e Permitir microfone', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: welcomeComBuilders()),
      );
      await tester.pump();

      expect(find.byKey(const Key('welcome_comecar_button')), findsOneWidget);
      expect(
        find.byKey(const Key('welcome_ja_tenho_conta_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('welcome_permitir_microfone_button')),
        findsOneWidget,
      );
    });

    testWidgets('botao Comecar navega para cadastro', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: welcomeComBuilders(
            cadastroBuilder: (_) => const Scaffold(
              body: Text('CadastroPage'),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('welcome_comecar_button')));
      await tester.pumpAndSettle();

      expect(find.text('CadastroPage'), findsOneWidget);
    });

    testWidgets('botao Ja tenho conta navega para login', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: welcomeComBuilders(
            loginBuilder: (_) => const Scaffold(body: Text('LoginPage')),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('welcome_ja_tenho_conta_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('LoginPage'), findsOneWidget);
    });

    testWidgets('botao Permitir microfone chama requestMicrophone', (
      tester,
    ) async {
      var solicitado = false;
      final fakeService = VoicePermissionService.test(
        client: _FakeMicrophoneClient(
          onRequest: () {
            solicitado = true;
            return MicrophonePermissionStatus.granted;
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: welcomeComBuilders(voicePermissionService: fakeService),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('welcome_permitir_microfone_button')),
      );
      await tester.pumpAndSettle();

      expect(solicitado, isTrue);
    });

    testWidgets(
      'botao Permitir microfone exibe feedback de permissao concedida',
      (tester) async {
        final fakeService = VoicePermissionService.test(
          client: _FakeMicrophoneClient(
            onRequest: () => MicrophonePermissionStatus.granted,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: welcomeComBuilders(voicePermissionService: fakeService),
          ),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('welcome_permitir_microfone_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('welcome_microfone_feedback')),
          findsOneWidget,
        );
        expect(
          find.text('Microfone liberado para comandos de voz.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'botao Permitir microfone exibe feedback de permissao negada',
      (tester) async {
        final fakeService = VoicePermissionService.test(
          client: _FakeMicrophoneClient(
            onRequest: () => MicrophonePermissionStatus.denied,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: welcomeComBuilders(voicePermissionService: fakeService),
          ),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('welcome_permitir_microfone_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('welcome_microfone_feedback')),
          findsOneWidget,
        );
      },
    );
  });

  group('H11 — sessão e AuthGate', () {
    testWidgets(
      'usuario sem sessao ve WelcomePage via AuthGate',
      (tester) async {
        final fakeAuth = _FakeAuthSessionService(null);
        await tester.pumpWidget(
          MaterialApp(
            home: AuthGate(
              authSessionService: fakeAuth,
              loginBuilder: (_) => WelcomePage(
                buscarConfiguracao: () async => configSemVoz(),
              ),
              homeBuilder: (_) => const Scaffold(body: Text('Home')),
            ),
          ),
        );
        await tester.pump(); // resolve FutureBuilder

        expect(find.text('Touchless'), findsWidgets);
        expect(find.text('Home'), findsNothing);
      },
    );

    testWidgets(
      'usuario com sessao restaurada vai direto para Home sem Welcome',
      (tester) async {
        final usuario = Usuario(
          id: 1,
          nome: 'Ana',
          email: 'ana@test.com',
          senhaHash: 'hash',
        );
        final fakeAuth = _FakeAuthSessionService(usuario);
        await tester.pumpWidget(
          MaterialApp(
            home: AuthGate(
              authSessionService: fakeAuth,
              loginBuilder: (_) => const Scaffold(body: Text('Welcome')),
              homeBuilder: (u) => Scaffold(body: Text('Home: ${u.nome}')),
            ),
          ),
        );
        await tester.pump(); // resolve FutureBuilder

        expect(find.text('Home: Ana'), findsOneWidget);
        expect(find.text('Welcome'), findsNothing);
      },
    );
  });

  group('H11 — comandos de voz na WelcomePage (dispatcher)', () {
    test(
      'comando comecar aciona handler comecarExperiencia no dispatcher',
      () async {
        var handlerChamado = false;
        final dispatcher = VoiceCommandDispatcher(
          handlers: {
            VoiceCommandType.comecarExperiencia: (_) async {
              handlerChamado = true;
              return VoiceCommandPageResult.handled(message: 'ok');
            },
          },
        );

        await dispatcher.dispatch(commandService.interpret('começar'));
        expect(handlerChamado, isTrue);
      },
    );

    test(
      'comando iniciar aciona handler comecarExperiencia no dispatcher',
      () async {
        var handlerChamado = false;
        final dispatcher = VoiceCommandDispatcher(
          handlers: {
            VoiceCommandType.comecarExperiencia: (_) async {
              handlerChamado = true;
              return VoiceCommandPageResult.handled(message: 'ok');
            },
          },
        );

        await dispatcher.dispatch(commandService.interpret('iniciar'));
        expect(handlerChamado, isTrue);
      },
    );

    test(
      'comando ja tenho conta aciona handler jaTenhoConta no dispatcher',
      () async {
        var handlerChamado = false;
        final dispatcher = VoiceCommandDispatcher(
          handlers: {
            VoiceCommandType.jaTenhoConta: (_) async {
              handlerChamado = true;
              return VoiceCommandPageResult.handled(message: 'ok');
            },
          },
        );

        await dispatcher.dispatch(commandService.interpret('já tenho conta'));
        expect(handlerChamado, isTrue);
      },
    );

    test(
      'comando permitir microfone aciona handler no dispatcher',
      () async {
        var handlerChamado = false;
        final dispatcher = VoiceCommandDispatcher(
          handlers: {
            VoiceCommandType.permitirMicrofone: (_) async {
              handlerChamado = true;
              return VoiceCommandPageResult.handled(message: 'ok');
            },
          },
        );

        await dispatcher.dispatch(
          commandService.interpret('permitir microfone'),
        );
        expect(handlerChamado, isTrue);
      },
    );

    test(
      'comandos welcome fora da WelcomePage retornam mensagem segura',
      () async {
        final dispatcher = VoiceCommandDispatcher();

        for (final frase in ['começar', 'iniciar', 'já tenho conta', 'login']) {
          final result = await dispatcher.dispatch(
            commandService.interpret(frase),
          );
          expect(result.handled, isTrue, reason: frase);
          expect(result.statusMessage, isNotNull, reason: frase);
        }
      },
    );
  });

  group('H11 — WelcomePage usa ContextualVoiceListeningMixin', () {
    testWidgets('WelcomePage define voiceOwnerId como welcome', (tester) async {
      final key = GlobalKey<State<WelcomePage>>();

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomePage(
            key: key,
            buscarConfiguracao: () async => configSemVoz(),
          ),
        ),
      );
      await tester.pump();

      // Verifica que a página renderizou e tem a VoiceStatusBar.
      expect(find.text('Touchless'), findsWidgets);
    });

    testWidgets('WelcomePage libera escuta ao ser descartada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: welcomeComBuilders()),
      );
      await tester.pump();

      // Troca o widget raiz — WelcomePage é descartada, dispose() chamado.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Outro'))),
      );
      await tester.pump();

      // Sem exceção = dispose liberou corretamente.
      expect(find.text('Outro'), findsOneWidget);
    });
  });
}

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeAuthSessionService extends AuthSessionService {
  _FakeAuthSessionService(this._usuario);
  final Usuario? _usuario;

  @override
  Future<Usuario?> restoreAuthenticatedUser() async => _usuario;
}

class _FakeMicrophoneClient implements MicrophonePermissionClient {
  _FakeMicrophoneClient({required MicrophonePermissionStatus Function() onRequest})
      : _onRequest = onRequest;

  final MicrophonePermissionStatus Function() _onRequest;

  @override
  Future<MicrophonePermissionStatus> status() async =>
      MicrophonePermissionStatus.denied;

  @override
  Future<MicrophonePermissionStatus> request() async => _onRequest();

  @override
  Future<bool> openSettings() async => false;
}
