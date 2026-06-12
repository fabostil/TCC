import 'dart:async';

import 'package:app_voz/features/voices/pages/cadastro_page.dart';
import 'package:app_voz/features/voices/services/auth_service.dart';
import 'package:app_voz/features/voices/services/google_auth_service.dart';
import 'package:app_voz/models/google_identity.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CadastroPage', () {
    testWidgets('renderiza campos e acoes principais sem loading inicial', (
      tester,
    ) async {
      final auth = _CadastroAuthFake();

      await _pumpCadastro(tester, auth: auth.service);

      expect(find.byKey(const Key('cadastro_nome_field')), findsOneWidget);
      expect(find.byKey(const Key('cadastro_email_field')), findsOneWidget);
      expect(find.byKey(const Key('cadastro_password_field')), findsOneWidget);
      expect(
        find.byKey(const Key('cadastro_confirm_password_field')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cadastro_submit_button')), findsOneWidget);
      expect(find.byKey(const Key('cadastro_google_button')), findsOneWidget);
      expect(find.text('Ja tenho uma conta'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('valida campos obrigatorios antes de cadastrar', (
      tester,
    ) async {
      final auth = _CadastroAuthFake();

      await _pumpCadastro(tester, auth: auth.service);
      await tester.ensureVisible(
        find.byKey(const Key('cadastro_submit_button')),
      );
      await tester.tap(find.byKey(const Key('cadastro_submit_button')));
      await tester.pump();

      expect(find.text('Informe seu nome.'), findsOneWidget);
      expect(find.text('Informe seu e-mail.'), findsOneWidget);
      expect(find.text('Informe uma senha.'), findsOneWidget);
      expect(find.text('Confirme sua senha.'), findsOneWidget);
      expect(auth.registerCalls, 0);
      expect(auth.googleCalls, 0);
    });

    testWidgets('valida nome, e-mail, senha e confirmacao reais', (
      tester,
    ) async {
      final auth = _CadastroAuthFake();

      await _pumpCadastro(tester, auth: auth.service);
      await tester.enterText(
        find.byKey(const Key('cadastro_nome_field')),
        'An',
      );
      await tester.enterText(
        find.byKey(const Key('cadastro_email_field')),
        'email-invalido',
      );
      await tester.enterText(
        find.byKey(const Key('cadastro_password_field')),
        'senhafraca',
      );
      await tester.enterText(
        find.byKey(const Key('cadastro_confirm_password_field')),
        'outra',
      );
      await tester.ensureVisible(
        find.byKey(const Key('cadastro_submit_button')),
      );
      await tester.tap(find.byKey(const Key('cadastro_submit_button')));
      await tester.pump();

      expect(
        find.text('O nome deve ter pelo menos 3 caracteres.'),
        findsOneWidget,
      );
      expect(find.text('Informe um e-mail valido.'), findsOneWidget);
      expect(find.text('Use letras e numeros na senha.'), findsOneWidget);
      expect(find.text('As senhas nao conferem.'), findsOneWidget);
      expect(auth.registerCalls, 0);
    });

    testWidgets('exibe erro quando cadastro local falha', (tester) async {
      final auth = _CadastroAuthFake(registerResult: false);

      await _pumpCadastro(tester, auth: auth.service);
      await _preencherCadastro(tester);
      await tester.tap(find.byKey(const Key('cadastro_submit_button')));
      await tester.pump();

      expect(find.text('Este e-mail ja esta cadastrado.'), findsOneWidget);
      expect(find.text('Login destino'), findsNothing);
      expect(auth.registerCalls, 1);
    });

    testWidgets('navega para login quando cadastro local tem sucesso', (
      tester,
    ) async {
      final auth = _CadastroAuthFake(registerResult: true);

      await _pumpCadastro(tester, auth: auth.service);
      await _preencherCadastro(tester);
      await tester.tap(find.byKey(const Key('cadastro_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Login destino'), findsOneWidget);
      expect(auth.registerCalls, 1);
    });

    testWidgets('mantem usuario no cadastro quando Google e cancelado', (
      tester,
    ) async {
      final auth = _CadastroAuthFake(googleCanceled: true);

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();

      expect(find.byType(CadastroPage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.registerCalls, 0);
      expect(auth.googleCalls, 1);
    });

    testWidgets('navega para home quando Google retorna usuario', (
      tester,
    ) async {
      final auth = _CadastroAuthFake(googleResult: _usuario);

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
      expect(auth.registerCalls, 0);
      expect(auth.googleCalls, 1);
    });

    testWidgets('Google Login com sucesso remove Cadastro da pilha', (
      tester,
    ) async {
      final auth = _CadastroAuthFake(googleResult: _usuario);

      await _pumpCadastroBehindPreviousRoute(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('open_cadastro_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);
      expect(find.text('Rota anterior'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home destino'), findsOneWidget);
      expect(find.byType(CadastroPage), findsNothing);
      expect(find.text('Rota anterior'), findsNothing);
    });

    testWidgets('exibe mensagem amigavel quando Google falha', (tester) async {
      final auth = _CadastroAuthFake(
        googleError: const GoogleAuthException(googleLoginConfigurationMessage),
      );

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();

      expect(find.text(googleLoginConfigurationMessage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.googleCalls, 1);
    });

    testWidgets('exibe mensagem amigavel quando conta local falha', (
      tester,
    ) async {
      final auth = _CadastroAuthFake(
        googleError: const AuthGoogleLoginException(
          authGoogleAccountPreparationMessage,
        ),
      );

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();

      expect(find.text(authGoogleAccountPreparationMessage), findsOneWidget);
      expect(find.text('Home destino'), findsNothing);
      expect(auth.googleCalls, 1);
    });

    testWidgets('desabilita botao local e mostra loading durante cadastro', (
      tester,
    ) async {
      final completer = Completer<bool>();
      final auth = _CadastroAuthFake(registerCompleter: completer);

      await _pumpCadastro(tester, auth: auth.service);
      await _preencherCadastro(tester);
      await tester.tap(find.byKey(const Key('cadastro_submit_button')));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('cadastro_submit_button')),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Login destino'), findsOneWidget);
    });

    testWidgets('desabilita botao Google e mostra loading durante Google', (
      tester,
    ) async {
      final completer = Completer<GoogleIdentity?>();
      final auth = _CadastroAuthFake(googleCompleter: completer);

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('cadastro_google_button')),
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
      final auth = _CadastroAuthFake(googleCompleter: completer);

      await _pumpCadastro(tester, auth: auth.service);
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.tap(find.byKey(const Key('cadastro_google_button')));
      await tester.pump();

      expect(auth.googleCalls, 1);

      completer.complete(_googleIdentity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home destino'), findsOneWidget);
    });
  });
}

Future<void> _pumpCadastro(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CadastroPage(
        authService: auth,
        homeBuilder: (_) => const _DestinationPage('Home destino'),
        loginBuilder: (_) => const _DestinationPage('Login destino'),
        logoBuilder: (_) =>
            const SizedBox(key: Key('test_logo'), width: 96, height: 96),
      ),
    ),
  );
}

Future<void> _pumpCadastroBehindPreviousRoute(
  WidgetTester tester, {
  required AuthService auth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _PreviousRoute(
        onOpenCadastro: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CadastroPage(
                authService: auth,
                homeBuilder: (_) => const _DestinationPage('Home destino'),
                logoBuilder: (_) => const SizedBox(
                  key: Key('test_logo'),
                  width: 96,
                  height: 96,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _preencherCadastro(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('cadastro_nome_field')),
    'Ana Silva',
  );
  await tester.enterText(
    find.byKey(const Key('cadastro_email_field')),
    'ana@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('cadastro_password_field')),
    'Senha123',
  );
  await tester.enterText(
    find.byKey(const Key('cadastro_confirm_password_field')),
    'Senha123',
  );
  await tester.ensureVisible(find.byKey(const Key('cadastro_submit_button')));
}

class _CadastroAuthFake {
  _CadastroAuthFake({
    this.registerResult = true,
    this.googleResult,
    this.googleCanceled = false,
    this.googleError,
    Completer<bool>? registerCompleter,
    Completer<GoogleIdentity?>? googleCompleter,
  }) : _registerCompleter = registerCompleter,
       _googleCompleter = googleCompleter;

  final bool registerResult;
  final Usuario? googleResult;
  final bool googleCanceled;
  final Object? googleError;
  final Completer<bool>? _registerCompleter;
  final Completer<GoogleIdentity?>? _googleCompleter;

  int registerCalls = 0;
  int googleCalls = 0;

  late final AuthService service = AuthService(
    localRegister: ({required nome, required email, required senha}) {
      registerCalls++;
      final completer = _registerCompleter;
      if (completer != null) {
        return completer.future;
      }
      return Future.value(registerResult);
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
  const _PreviousRoute({required this.onOpenCadastro});

  final void Function(BuildContext context) onOpenCadastro;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Rota anterior'),
            ElevatedButton(
              key: const Key('open_cadastro_button'),
              onPressed: () => onOpenCadastro(context),
              child: const Text('Abrir cadastro'),
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
