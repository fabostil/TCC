import 'package:app_voz/features/home/pages/home_page.dart';
import 'package:app_voz/features/voices/services/auth_session_service.dart';
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

        expect(find.text('Ola, Ana Silva'), findsOneWidget);
        expect(find.text('Novo projeto'), findsOneWidget);
        expect(find.text('Meus projetos'), findsOneWidget);
        expect(find.text('Minhas gravacoes'), findsOneWidget);
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Historico'), findsOneWidget);
        expect(find.text('Configuracoes'), findsOneWidget);
        expect(
          find.text(
            'Modo manual ativo. Voce pode habilitar comandos de voz em Configuracoes.',
          ),
          findsOneWidget,
        );
        expect(permissionClient.requestCalls, 0);
        expect(permissionClient.openSettingsCalls, 0);
      },
    );

    testWidgets('logout confirmado encerra sessao e navega para login', (
      tester,
    ) async {
      var logoutCalls = 0;
      final authSession = _authSessionService(
        googleSignOut: () async {
          logoutCalls++;
        },
      );

      await _pumpHome(tester, authSession: authSession);
      await tester.pump();

      await tester.tap(find.byKey(const Key('home_logout_button')));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(logoutCalls, 1);
      expect(find.byKey(const Key('login_destination')), findsOneWidget);
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

      await tester.tap(find.byKey(const Key('home_logout_button')));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sair'));
      await tester.pump();

      expect(logoutCalls, 1);
      expect(
        find.text('Nao foi possivel sair da conta. Tente novamente.'),
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
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  AuthSessionService? authSession,
  _FakePermissionClient? permissionClient,
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
      ),
    ),
  );
}

AuthSessionService _authSessionService({
  Future<void> Function()? googleSignOut,
}) {
  return AuthSessionService(
    stopActiveVoiceSession: () async {},
    clearActiveVoiceContext: () {},
    clearRuntimeVoiceSession: () {},
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
