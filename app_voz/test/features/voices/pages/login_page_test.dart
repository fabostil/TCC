import 'dart:async';

import 'package:app_voz/features/voices/pages/cadastro_page.dart';
import 'package:app_voz/features/voices/pages/login_page.dart';
import 'package:app_voz/features/voices/services/auth_service.dart';
import 'package:app_voz/features/voices/services/google_auth_service.dart';
import 'package:app_voz/models/google_identity.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginPage', () {
    testWidgets('renderiza campos e acoes principais sem loading inicial', (
      tester,
    ) async {
      final auth = _LoginAuthFake();

      await _pumpLogin(tester, auth: auth.service);

      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
      expect(find.byKey(const Key('login_google_button')), findsOneWidget);
      expect(find.text('Esqueci minha senha'), findsOneWidget);
      expect(find.text('Criar nova conta'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('botao de visibilidade da senha tem descricao acessivel', (
      tester,
    ) async {
      final auth = _LoginAuthFake();

      await _pumpLogin(tester, auth: auth.service);

      expect(find.byTooltip('Mostrar senha'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar senha'));
      await tester.pump();

      expect(find.byTooltip('Ocultar senha'), findsOneWidget);
    });

    testWidgets('mostra orientação honesta para recuperação de senha', (
      tester,
    ) async {
      final auth = _LoginAuthFake();

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('forgot_password_button')));
      await tester.pumpAndSettle();

      expect(find.text('Recuperação de senha'), findsOneWidget);
      expect(find.text('Entendi'), findsOneWidget);

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      final message = (dialog.content! as Text).data!.toLowerCase();
      expect(message, contains('recuperação automática por e-mail'));
      expect(message, contains('entrar com google'));
      expect(message, contains('crie uma nova conta'));
      expect(message, isNot(contains('e-mail enviado')));
      expect(message, isNot(contains('sqlite')));
      expect(message, isNot(contains('hash')));
      expect(message, isNot(contains('salt')));
      expect(message, isNot(contains('banco de dados')));
    });

    testWidgets(
      'fecha orientação sem autenticar, alterar conta ou abrir Home',
      (tester) async {
        final auth = _LoginAuthFake();

        await _pumpLogin(tester, auth: auth.service);
        await tester.tap(find.byKey(const Key('forgot_password_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('password_recovery_dismiss_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recuperação de senha'), findsNothing);
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('Home destino'), findsNothing);
        expect(auth.localCalls, 0);
        expect(auth.googleCalls, 0);
      },
    );

    testWidgets('valida campos obrigatorios antes de autenticar', (
      tester,
    ) async {
      final auth = _LoginAuthFake();

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(find.text('Informe seu e-mail.'), findsOneWidget);
      expect(find.text('Digite sua senha para continuar.'), findsOneWidget);
      expect(auth.localCalls, 0);
      expect(auth.googleCalls, 0);
    });

    testWidgets('exibe erro quando login local retorna null', (tester) async {
      final auth = _LoginAuthFake(localResult: null);

      await _pumpLogin(tester, auth: auth.service);
      await _preencherLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(
        find.text('Não foi possível entrar. Confira o e-mail e a senha.'),
        findsOneWidget,
      );
      expect(find.text('Home destino'), findsNothing);
      expect(auth.localCalls, 1);
      expect(auth.googleCalls, 0);
    });

    testWidgets('navega para home quando login local retorna usuario', (
      tester,
    ) async {
      final auth = _LoginAuthFake(localResult: _usuario);

      await _pumpLogin(tester, auth: auth.service);
      await _preencherLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
      expect(auth.localCalls, 1);
      expect(auth.googleCalls, 0);
    });

    testWidgets('login local com sucesso remove rotas anteriores da pilha', (
      tester,
    ) async {
      final auth = _LoginAuthFake(localResult: _usuario);

      await _pumpLoginBehindPreviousRoute(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('open_login_button')));
      await tester.pumpAndSettle();
      await _preencherLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);
      expect(find.text('Rota anterior'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('Rota anterior'), findsNothing);
    });

    testWidgets('mantem usuario no login quando Google e cancelado', (
      tester,
    ) async {
      final auth = _LoginAuthFake(googleCanceled: true);

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.localCalls, 0);
      expect(auth.googleCalls, 1);
    });

    testWidgets('navega para home quando Google retorna usuario', (
      tester,
    ) async {
      final auth = _LoginAuthFake(googleResult: _usuario);

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
      expect(auth.localCalls, 0);
      expect(auth.googleCalls, 1);
    });

    testWidgets('Google Login com sucesso remove Login da pilha', (
      tester,
    ) async {
      final auth = _LoginAuthFake(googleResult: _usuario);

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets(
      'Google Login pelo cadastro aberto a partir do login limpa Login e Cadastro',
      (tester) async {
        final auth = _LoginAuthFake(googleResult: _usuario);

        await _pumpLoginWithCadastro(tester, auth: auth.service);
        await tester.ensureVisible(find.text('Criar nova conta'));
        await tester.tap(find.text('Criar nova conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cadastro_google_button')));
        await tester.pumpAndSettle();

        expect(find.text('Home destino'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.text('Home destino'), findsOneWidget);
        expect(find.byType(LoginPage), findsNothing);
        expect(find.text('Criar conta'), findsNothing);
      },
    );

    testWidgets('exibe mensagem amigavel quando Google falha', (tester) async {
      final auth = _LoginAuthFake(
        googleError: const GoogleAuthException(googleLoginConfigurationMessage),
      );

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();

      expect(find.text(googleLoginConfigurationMessage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.googleCalls, 1);
    });

    testWidgets('exibe mensagem amigavel quando conta local falha', (
      tester,
    ) async {
      final auth = _LoginAuthFake(
        googleError: const AuthGoogleLoginException(
          authGoogleAccountPreparationMessage,
        ),
      );

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();

      expect(find.text(authGoogleAccountPreparationMessage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.googleCalls, 1);
    });

    testWidgets('desabilita botao local e mostra loading durante login', (
      tester,
    ) async {
      final completer = Completer<Usuario?>();
      final auth = _LoginAuthFake(localCompleter: completer);

      await _pumpLogin(tester, auth: auth.service);
      await _preencherLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('login_submit_button')),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_usuario);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
    });

    testWidgets('desabilita botao Google e mostra loading durante Google', (
      tester,
    ) async {
      final completer = Completer<GoogleIdentity?>();
      final auth = _LoginAuthFake(googleCompleter: completer);

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('login_google_button')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_googleIdentity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
    });

    testWidgets('botao Google ignora toque duplicado durante tentativa', (
      tester,
    ) async {
      final completer = Completer<GoogleIdentity?>();
      final auth = _LoginAuthFake(googleCompleter: completer);

      await _pumpLogin(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump();

      expect(auth.googleCalls, 1);

      completer.complete(_googleIdentity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
    });
  });
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LoginPage(
        authService: auth,
        homeBuilder: (_) => const _DestinationPage('Home destino'),
        logoBuilder: (_) =>
            const SizedBox(key: Key('test_logo'), width: 112, height: 112),
      ),
    ),
  );
}

Future<void> _pumpLoginBehindPreviousRoute(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _PreviousRoute(
        onOpenLogin: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LoginPage(
                authService: auth,
                homeBuilder: (_) => const _DestinationPage('Home destino'),
                logoBuilder: (_) => const SizedBox(
                  key: Key('test_logo'),
                  width: 112,
                  height: 112,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _pumpLoginWithCadastro(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LoginPage(
        authService: auth,
        homeBuilder: (_) => const _DestinationPage('Home destino'),
        cadastroBuilder: (_) => CadastroPage(
          authService: auth,
          homeBuilder: (_) => const _DestinationPage('Home destino'),
          logoBuilder: (_) =>
              const SizedBox(key: Key('test_logo'), width: 96, height: 96),
        ),
        logoBuilder: (_) =>
            const SizedBox(key: Key('test_logo'), width: 112, height: 112),
      ),
    ),
  );
}

Future<void> _preencherLogin(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login_email_field')),
    'ana@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login_password_field')),
    'Senha123',
  );
}

class _LoginAuthFake {
  _LoginAuthFake({
    this.localResult,
    this.googleResult,
    this.googleCanceled = false,
    this.googleError,
    Completer<Usuario?>? localCompleter,
    Completer<GoogleIdentity?>? googleCompleter,
  }) : _localCompleter = localCompleter,
       _googleCompleter = googleCompleter;

  final Usuario? localResult;
  final Usuario? googleResult;
  final bool googleCanceled;
  final Object? googleError;
  final Completer<Usuario?>? _localCompleter;
  final Completer<GoogleIdentity?>? _googleCompleter;

  int localCalls = 0;
  int googleCalls = 0;

  late final AuthService service = AuthService(
    localAuthenticator: ({required email, required senha}) {
      localCalls++;
      final completer = _localCompleter;
      if (completer != null) {
        return completer.future;
      }
      return Future.value(localResult);
    },
    googleIdentityProvider: () {
      googleCalls++;
      final error = googleError;
      if (error != null) {
        return Future.error(error);
      }
      final completer = _googleCompleter;
      if (completer != null) {
        return completer.future;
      }
      if (googleCanceled) {
        return Future.value();
      }
      return Future.value(_googleIdentity);
    },
    googleUserResolver:
        ({required nome, required email, required googleId, fotoUrl}) async {
          return googleResult ?? _usuario;
        },
  );
}

class _DestinationPage extends StatelessWidget {
  const _DestinationPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

class _PreviousRoute extends StatelessWidget {
  const _PreviousRoute({required this.onOpenLogin});

  final void Function(BuildContext context) onOpenLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Rota anterior'),
            ElevatedButton(
              key: const Key('open_login_button'),
              onPressed: () => onOpenLogin(context),
              child: const Text('Abrir login'),
            ),
          ],
        ),
      ),
    );
  }
}

final _usuario = Usuario(
  id: 1,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

const _googleIdentity = GoogleIdentity(
  googleId: 'google-1',
  nome: 'Ana Silva',
  email: 'ana@example.com',
  idToken: 'token',
);
