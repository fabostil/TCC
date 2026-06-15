import 'dart:io';

import 'package:app_voz/features/home/pages/home_page.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/services/auth_session_service.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/features/voices/services/voice_permission_service.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomePage', () {
    testWidgets(
      'renderiza usuario, atalhos principais e nao solicita permissao',
      (tester) async {
        final permissionClient = _FakePermissionClient();

        await _pumpHome(tester, permissionClient: permissionClient);
        await tester.pump();

        expect(find.text('Olá, Ana Silva'), findsOneWidget);
        expect(find.text('Novo projeto'), findsOneWidget);
        expect(find.text('Meus projetos'), findsOneWidget);
        expect(find.text('Minhas gravações'), findsOneWidget);
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Histórico'), findsOneWidget);
        expect(find.text('Configurações'), findsOneWidget);
        expect(
          find.text(
            'Modo manual ativo. Você pode habilitar comandos de voz em Configurações.',
          ),
          findsOneWidget,
        );
        expect(permissionClient.requestCalls, 0);
        expect(permissionClient.openSettingsCalls, 0);
      },
    );

    testWidgets('abre e fecha ajuda de comandos por voz pela Home', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.pump();

      expect(find.text('Ver comandos de voz'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_voice_command_help_button')));
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsOneWidget);
      expect(find.text('Meus projetos'), findsAtLeastNWidgets(1));
      expect(find.text('Minhas gravações'), findsAtLeastNWidgets(1));
      expect(find.text('Tela inicial'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('voice_command_help_close_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Comandos de voz'), findsNothing);
    });

    testWidgets('logout confirmado encerra sessao e navega para login', (
      tester,
    ) async {
      var logoutCalls = 0;
      var confirmationCalls = 0;
      final authSession = _authSessionService(
        googleSignOut: () async {
          logoutCalls++;
        },
      );

      await _pumpHome(
        tester,
        authSession: authSession,
        confirmarLogout: () async {
          confirmationCalls++;
          return true;
        },
      );
      await tester.pump();

      await _triggerLogout(tester);
      await tester.pumpAndSettle();

      expect(confirmationCalls, 1);
      expect(logoutCalls, 1);
      expect(find.byKey(const Key('login_destination')), findsOneWidget);
    });

    testWidgets('logout confirmado remove Home da pilha de navegacao', (
      tester,
    ) async {
      final authSession = _authSessionService();

      await _pumpHome(tester, authSession: authSession);
      await tester.pump();

      await _triggerLogout(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_destination')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_destination')), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('erro no logout mostra mensagem e permanece na home', (
      tester,
    ) async {
      var logoutCalls = 0;
      final authSession = _authSessionService(
        googleSignOut: () async {
          logoutCalls++;
          throw StateError('falha logout');
        },
      );

      await _pumpHome(tester, authSession: authSession);
      await tester.pump();

      await _triggerLogout(tester);
      await tester.pump();

      expect(logoutCalls, 1);
      expect(
        find.text('Não consegui sair da conta agora. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('Login destino'), findsNothing);
    });

    testWidgets('constroi com voz desabilitada sem iniciar escuta real', (
      tester,
    ) async {
      final permissionClient = _FakePermissionClient();

      await _pumpHome(tester, permissionClient: permissionClient);
      await tester.pump();

      final micButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.mic_none_rounded).last,
      );
      expect(micButton.onPressed, isNull);
      expect(find.text('Assistente de voz aguardando.'), findsOneWidget);
      expect(permissionClient.statusCalls, 0);
      expect(permissionClient.requestCalls, 0);
    });

    testWidgets('comando descer rola a Home por voz', (tester) async {
      await _pumpHome(tester);
      await tester.pump();
      final scrollView = _homeScrollView(tester);
      final before = scrollView.controller!.offset;

      final result = await _dispatchHomeCommandAndSettle(tester, 'descer');

      expect(result.handled, isTrue);
      expect(result.statusMessage, 'Rolando para baixo.');
      expect(scrollView.controller!.offset, greaterThan(before));
    });

    testWidgets('comando subir rola a Home para cima por voz', (tester) async {
      await _pumpHome(tester);
      await tester.pump();
      final controller = _homeScrollView(tester).controller!;
      controller.jumpTo(300);
      await tester.pump();

      final result = await _dispatchHomeCommandAndSettle(tester, 'subir');

      expect(result.handled, isTrue);
      expect(result.statusMessage, 'Rolando para cima.');
      expect(controller.offset, lessThan(300));
    });

    testWidgets('comando ir para o topo volta a Home ao inicio', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.pump();
      final controller = _homeScrollView(tester).controller!;
      controller.jumpTo(300);
      await tester.pump();

      final result = await _dispatchHomeCommandAndSettle(
        tester,
        'ir para o topo',
      );

      expect(result.handled, isTrue);
      expect(result.statusMessage, 'Indo para o topo.');
      expect(controller.offset, 0);
    });

    testWidgets('comando ir para o fim chega ao final real da Home', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.pump();
      final controller = _homeScrollView(tester).controller!;

      final result = await _dispatchHomeCommandAndSettle(
        tester,
        'ir para o fim',
      );

      expect(result.handled, isTrue);
      expect(result.statusMessage, 'Indo para o fim da lista.');
      expect(controller.offset, controller.position.maxScrollExtent);
    });

    testWidgets('tela inicial e voltar continuam como navegacao na Home', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.pump();
      final controller = _homeScrollView(tester).controller!;
      controller.jumpTo(250);
      await tester.pump();

      final telaInicial = await _dispatchHomeCommandAndSettle(
        tester,
        'tela inicial',
      );
      final offsetAfterTelaInicial = controller.offset;
      final voltar = await _dispatchHomeCommandAndSettle(tester, 'voltar');

      expect(telaInicial.handled, isTrue);
      expect(voltar.handled, isTrue);
      expect(controller.offset, offsetAfterTelaInicial);
    });

    testWidgets('descricao nao executa acao global na Home', (tester) async {
      await _pumpHome(tester);
      await tester.pump();

      final result = await _dispatchHomeCommandAndSettle(tester, 'descricao');

      expect(result.handled, isTrue);
      expect(
        result.statusMessage,
        'Comando não executável nesta tela.',
      );
    });
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  AuthSessionService? authSession,
  _FakePermissionClient? permissionClient,
  HomeLogoutConfirmation? confirmarLogout,
}) async {
  final client = permissionClient ?? _FakePermissionClient();

  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        usuario: _usuario,
        authSessionService: authSession ?? _authSessionService(),
        voicePermissionService: VoicePermissionService.test(client: client),
        buscarConfiguracao: () async => _configuracaoVozDesativada,
        concluirPrimeiraExecucao: ({required comandosVozAtivos}) async {},
        loginBuilder: () => const _DestinationPage(
          key: Key('login_destination'),
          label: 'Login destino',
        ),
        confirmarLogout: confirmarLogout ?? () async => true,
      ),
    ),
  );
}

SingleChildScrollView _homeScrollView(WidgetTester tester) {
  return tester.widget<SingleChildScrollView>(
    find.byType(SingleChildScrollView),
  );
}

Future<VoiceCommandPageResult> _dispatchHomeCommandAndSettle(
  WidgetTester tester,
  String text,
) async {
  final state = tester.state(find.byType(HomePage)) as dynamic;
  final result = const CommandService().interpret(text);
  final future =
      state.voiceCommandDispatcher.dispatch(result)
          as Future<VoiceCommandPageResult>;
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 20));
  return future;
}

Future<void> _triggerLogout(WidgetTester tester) async {
  final button = tester.widget<IconButton>(
    find.byKey(const Key('home_logout_button')),
  );
  expect(button.tooltip, 'Sair');
  await tester.runAsync(() async {
    final result = Function.apply(button.onPressed!, const []);
    if (result is Future<void>) {
      await result;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();
}

AuthSessionService _authSessionService({
  Future<void> Function()? googleSignOut,
}) {
  return AuthSessionService(
    stopActiveVoiceSession: () async {},
    clearActiveVoiceContext: () {},
    clearRuntimeVoiceSession: () {},
    sessionDirectoryPathProvider: () async =>
        Directory.systemTemp.createTempSync('home_auth_session_test').path,
    googleSignOut: googleSignOut ?? () async {},
  );
}

class _FakePermissionClient implements MicrophonePermissionClient {
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<MicrophonePermissionStatus> status() async {
    statusCalls++;
    return MicrophonePermissionStatus.denied;
  }

  @override
  Future<MicrophonePermissionStatus> request() async {
    requestCalls++;
    return MicrophonePermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return false;
  }
}

class _DestinationPage extends StatelessWidget {
  const _DestinationPage({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

final _configuracaoVozDesativada = ConfiguracaoApp(
  comandosVozAtivos: false,
  primeiraExecucaoConcluida: true,
  escutaContinua: false,
  feedbackSonoro: false,
  paradaSilencio: true,
  tempoSilencioSegundos: 6,
  temaEscuro: false,
  dataAtualizacao: '2026-06-10T00:00:00.000',
);
