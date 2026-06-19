import 'package:app_voz/core/ui/voice_status_bar.dart';
import 'package:app_voz/features/onboarding/pages/microphone_permission_page.dart';
import 'package:app_voz/features/voices/services/voice_permission_service.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fake MicrophonePermissionClient ──────────────────────────────────────────

class _FakeClient implements MicrophonePermissionClient {
  _FakeClient({
    required MicrophonePermissionStatus statusResult,
    MicrophonePermissionStatus requestResult =
        MicrophonePermissionStatus.denied,
  })  : _statusResult = statusResult,
        _requestResult = requestResult;

  final MicrophonePermissionStatus _statusResult;
  final MicrophonePermissionStatus _requestResult;

  @override
  Future<MicrophonePermissionStatus> status() async => _statusResult;

  @override
  Future<MicrophonePermissionStatus> request() async => _requestResult;

  @override
  Future<bool> openSettings() async => false;
}

VoicePermissionService _service({
  MicrophonePermissionStatus checkResult = MicrophonePermissionStatus.denied,
  MicrophonePermissionStatus requestResult = MicrophonePermissionStatus.denied,
}) {
  return VoicePermissionService.test(
    client: _FakeClient(
      statusResult: checkResult,
      requestResult: requestResult,
    ),
  );
}

void main() {
  final usuario = Usuario(
    id: 1,
    nome: 'Teste',
    email: 'test@example.com',
    senhaHash: 'hash',
  );

  Widget buildPage({
    required VoicePermissionService permissionService,
    Widget Function(Usuario)? homeBuilder,
  }) {
    return MaterialApp(
      home: MicrophonePermissionPage(
        usuario: usuario,
        voicePermissionService: permissionService,
        homeBuilder: homeBuilder,
      ),
    );
  }

  // ── Teste 21: Não exibe VoiceStatusBar ─────────────────────────────────────
  testWidgets('nao exibe VoiceStatusBar', (tester) async {
    await tester.pumpWidget(
      buildPage(permissionService: _service()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VoiceStatusBar), findsNothing);
  });

  // ── Teste 22: Se microfone já concedido → vai para home sem mostrar UI ────
  testWidgets('se microfone ja concedido vai para home diretamente',
      (tester) async {
    var homeBuilt = false;
    await tester.pumpWidget(
      buildPage(
        permissionService:
            _service(checkResult: MicrophonePermissionStatus.granted),
        homeBuilder: (u) {
          homeBuilt = true;
          return const Scaffold(body: Text('Home'));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(homeBuilt, isTrue);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ative o controle por voz'), findsNothing);
  });

  // ── Teste 23: Exibe UI quando microfone não concedido ──────────────────────
  testWidgets('exibe UI de permissao quando microfone nao concedido',
      (tester) async {
    await tester.pumpWidget(
      buildPage(permissionService: _service()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ative o controle por voz'), findsOneWidget);
    expect(
      find.byKey(const Key('mic_permission_allow_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mic_permission_skip_button')),
      findsOneWidget,
    );
  });

  // ── Teste 24a: Permitir microfone → concedido → vai para home ─────────────
  testWidgets('permitir microfone e ir para home apos concessao',
      (tester) async {
    var homeBuilt = false;
    await tester.pumpWidget(
      buildPage(
        permissionService: _service(
          requestResult: MicrophonePermissionStatus.granted,
        ),
        homeBuilder: (u) {
          homeBuilt = true;
          return const Scaffold(body: Text('Home Concedido'));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mic_permission_allow_button')));
    // Aguarda o feedback e o delay de 900ms antes da navegação
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(homeBuilt, isTrue);
    expect(find.text('Home Concedido'), findsOneWidget);
  });

  // ── Teste 24b: Botão Permitir microfone → negado → exibe feedback ──────────
  testWidgets('exibe feedback quando permissao negada', (tester) async {
    await tester.pumpWidget(
      buildPage(permissionService: _service()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mic_permission_allow_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mic_permission_feedback')), findsOneWidget);
  });

  // ── Teste 24c: Continuar sem microfone navega para home ────────────────────
  testWidgets('continuar sem microfone navega para home', (tester) async {
    var homeBuilt = false;
    await tester.pumpWidget(
      buildPage(
        permissionService: _service(),
        homeBuilder: (u) {
          homeBuilt = true;
          return const Scaffold(body: Text('Home Sem Mic'));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mic_permission_skip_button')));
    await tester.pumpAndSettle();

    expect(homeBuilt, isTrue);
    expect(find.text('Home Sem Mic'), findsOneWidget);
  });

  // ── permanentlyDenied → feedback correto ──────────────────────────────────
  testWidgets('exibe feedback quando permissao permanentemente negada',
      (tester) async {
    await tester.pumpWidget(
      buildPage(
        permissionService: _service(
          requestResult: MicrophonePermissionStatus.permanentlyDenied,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mic_permission_allow_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mic_permission_feedback')), findsOneWidget);
  });
}
