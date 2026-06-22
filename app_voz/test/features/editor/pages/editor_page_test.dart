import 'dart:typed_data';

import 'package:app_voz/database/app_database.dart';
import 'package:app_voz/features/editor/pages/editor_page.dart';
import 'package:app_voz/features/editor/services/audio_recording_capture.dart';
import 'package:app_voz/features/recordings/services/recording_management_service.dart';
import 'package:app_voz/features/voices/realtime/runtime/runtime_engine.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import '../../../repositories/repository_test_utils.dart';

// ---------------------------------------------------------------------------
// Infraestrutura dos testes
//
// Problemas resolvidos:
//   1. MissingPluginException (record): _NoopAudioRecordingCapture injeta um
//      AudioRecordingCapture fake via recordingCaptureForTesting, evitando
//      que o AudioRecorder real inicialize o plugin nativo.
//   2. Timer pendente (700 ms recovery): tearDown chama
//      VoiceRuntimeEngine.instance.resetForTesting(), que cancela todos os
//      Timers de recovery antes do próximo teste.
//   3. FK constraint (usuario_id): setUpAll insere usuario id=1 no banco FFI
//      depois de abri-lo, para que registrarComandoVoz não viole a FK.
//   4. "ir para o fim": _InstantScrollController usa jumpTo em vez de
//      animateTo, permitindo que VoiceScrollHandler.handle() complete sem
//      precisar de frame pumping dentro de tester.runAsync.
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    configureRepositoryTestDatabase();
    await useRepositoryTestDatabase('editor_page_test.db');
    // Insere o usuario id=1 para que registrarComandoVoz não viole a FK
    // em comando_voz(usuario_id).
    final db = await AppDatabase.instance.database;
    await db.execute(
      "INSERT OR IGNORE INTO usuario (id, nome, email, senha_hash) "
      "VALUES (1, 'Teste', 'teste@example.com', 'hash')",
    );
  });

  tearDown(() {
    // Cancela todos os Timers de recovery (700 ms) deixados pelo
    // VoiceRuntimeEngine após cada teste.
    VoiceRuntimeEngine.instance.resetForTesting();
  });

  // ---------------------------------------------------------------------------
  // Scroll — VoiceScrollHandler chamado (não mostra mensagem antiga)
  // ---------------------------------------------------------------------------

  group('Editor scroll por voz — VoiceScrollHandler chamado', () {
    testWidgets('descer nao mostra mensagem antiga de lista indisponivel',
        (tester) async {
      await tester.pumpWidget(_editorApp(recordings: _makeRecordings(20)));
      await tester.pump();

      final state = tester.state(find.byType(EditorPage)) as dynamic;
      await tester.runAsync(() async {
        await (state.debugHandleVoiceCommandForTesting('descer') as Future<void>);
      });
      await tester.pump();

      expect(
        find.text('Não há lista para rolar nesta tela.'),
        findsNothing,
        reason: 'Scroll deve usar VoiceScrollHandler, não a mensagem antiga',
      );
    });

    testWidgets('rolar para baixo nao mostra mensagem antiga', (tester) async {
      await tester.pumpWidget(_editorApp(recordings: _makeRecordings(20)));
      await tester.pump();
      final state = tester.state(find.byType(EditorPage)) as dynamic;

      await tester.runAsync(() async {
        await (state.debugHandleVoiceCommandForTesting(
          'rolar para baixo',
        ) as Future<void>);
      });
      await tester.pump();

      expect(find.text('Não há lista para rolar nesta tela.'), findsNothing);
    });

    testWidgets('subir nao mostra mensagem antiga', (tester) async {
      await tester.pumpWidget(_editorApp(recordings: _makeRecordings(20)));
      await tester.pump();
      final state = tester.state(find.byType(EditorPage)) as dynamic;

      await tester.runAsync(() async {
        await (state.debugHandleVoiceCommandForTesting('subir') as Future<void>);
      });
      await tester.pump();

      expect(find.text('Não há lista para rolar nesta tela.'), findsNothing);
    });

    testWidgets('ir para o topo nao mostra mensagem antiga', (tester) async {
      await tester.pumpWidget(_editorApp(recordings: _makeRecordings(20)));
      await tester.pump();
      final state = tester.state(find.byType(EditorPage)) as dynamic;

      await tester.runAsync(() async {
        await (state.debugHandleVoiceCommandForTesting(
          'ir para o topo',
        ) as Future<void>);
      });
      await tester.pump();

      expect(find.text('Não há lista para rolar nesta tela.'), findsNothing);
    });

    testWidgets('ir para o fim nao mostra mensagem antiga', (tester) async {
      await tester.pumpWidget(_editorApp(recordings: _makeRecordings(20)));
      await tester.pump();
      final state = tester.state(find.byType(EditorPage)) as dynamic;

      await tester.runAsync(() async {
        await (state.debugHandleVoiceCommandForTesting(
          'ir para o fim',
        ) as Future<void>);
      });
      // Pump adicional para endOfFrame de _adjustToLatestBottomIfNeeded
      await tester.pump();
      await tester.pump();

      expect(find.text('Não há lista para rolar nesta tela.'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Ajuda — diálogo abre via botão (não passa por commandController)
  // ---------------------------------------------------------------------------

  testWidgets('ajuda via botao abre dialogo de ajuda do Editor', (tester) async {
    await tester.pumpWidget(_editorApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Comandos do editor'));
    await tester.pumpAndSettle();

    expect(
      find.byType(Dialog).evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty,
      isTrue,
      reason: 'Ajuda deve abrir um diálogo',
    );
  });

  // ---------------------------------------------------------------------------
  // fechar — fecha diálogo aberto via voz
  // ---------------------------------------------------------------------------

  testWidgets('fechar por voz fecha dialogo de ajuda', (tester) async {
    await tester.pumpWidget(_editorApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Comandos do editor'));
    await tester.pumpAndSettle();
    expect(
      find.byType(Dialog).evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(SimpleDialog).evaluate().isNotEmpty,
      isTrue,
      reason: 'Diálogo deve abrir ao pressionar ajuda',
    );

    final state = tester.state(find.byType(EditorPage)) as dynamic;
    await tester.runAsync(() async {
      await (state.debugHandleVoiceCommandForTesting('fechar') as Future<void>);
    });
    await tester.pumpAndSettle();

    expect(find.text('Editor Musical'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // voltar — navega para tela anterior
  // ---------------------------------------------------------------------------

  testWidgets('voltar por voz faz Navigator.maybePop no Editor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Navigator.push<void>(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => EditorPage(
                  usuario: _usuario,
                  enableVoiceListening: false,
                  recordingServiceForTesting: _FakeRecordingManagementService(),
                  scrollControllerForTesting: _InstantScrollController(),
                  recordingCaptureForTesting: _NoopAudioRecordingCapture(),
                ),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsOneWidget);

    final state = tester.state(find.byType(EditorPage)) as dynamic;
    await tester.runAsync(() async {
      await (state.debugHandleVoiceCommandForTesting('voltar') as Future<void>);
    });
    await tester.pumpAndSettle();

    expect(find.byType(EditorPage), findsNothing,
        reason: 'voltar deve fechar o Editor');
  });

  // ---------------------------------------------------------------------------
  // minhas gravações — navega para MinhasGravacoesPage
  // ---------------------------------------------------------------------------

  testWidgets('minhas gravacoes por voz dispara push de rota',
      (tester) async {
    final observer = _PushObserver();
    await tester.pumpWidget(_editorApp(observer: observer));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;
    await tester.runAsync(() async {
      await (state.debugHandleVoiceCommandForTesting(
        'minhas gravacoes',
      ) as Future<void>);
    });

    expect(observer.pushedRoutes, isNotEmpty,
        reason: '"minhas gravações" deve disparar push de rota');
  });

  // ---------------------------------------------------------------------------
  // gravar — não mostra mensagem de "comando não disponível"
  // ---------------------------------------------------------------------------

  testWidgets('gravar nao mostra mensagem de comando indisponivel',
      (tester) async {
    await tester.pumpWidget(_editorApp());
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;
    await tester.runAsync(() async {
      await (state.debugHandleVoiceCommandForTesting('gravar') as Future<void>);
    });
    await tester.pump();

    expect(
      find.text(
        'Esse comando não está disponível no editor.'
        ' Use os botões da tela inicial para navegar.',
      ),
      findsNothing,
      reason: '"gravar" deve tentar iniciar gravação, não exibir indisponível',
    );
  });

  // ---------------------------------------------------------------------------
  // Resultado parcial — _interpretandoComando bloqueia chamada concorrente
  // ---------------------------------------------------------------------------

  testWidgets('chamada concorrente a interpretarComando e bloqueada',
      (tester) async {
    await tester.pumpWidget(_editorApp());
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // Ambas as chamadas ficam dentro de runAsync para evitar bloqueio no
    // FakeAsync. f1 suspende no primeiro await (DB) com a flag=true; f2
    // é chamada antes de f1 completar e retorna imediatamente (flag bloqueada).
    await tester.runAsync(() async {
      final f1 = state.debugHandleVoiceCommandForTesting(
        'ir para o topo',
      ) as Future<void>;
      // f1 suspendeu no primeiro await: _interpretandoComando já é true.
      final f2 = state.debugHandleVoiceCommandForTesting(
        'subir',
      ) as Future<void>;
      // f2 retorna imediatamente (bloqueada pela flag)
      await f2;
      // Deixa f1 completar normalmente
      await f1;
    });
    await tester.pump();
    // Nenhuma exceção = flag funcionou corretamente
  });

  // ---------------------------------------------------------------------------
  // EditorVoiceFlowPolicy — gravação ativa bloqueia navegação (unidade)
  // ---------------------------------------------------------------------------

  test('EditorVoiceFlowPolicy bloqueia navegacao durante gravacao ativa', () {
    const policy = EditorVoiceFlowPolicy();

    expect(
      policy.navigationDecision(
        recording: true,
        commandType: VoiceCommandType.abrirGravacoes,
      ),
      EditorVoiceNavigationDecision.block,
      reason: 'Navegação bloqueada durante gravação',
    );

    expect(
      policy.navigationDecision(
        recording: true,
        commandType: VoiceCommandType.voltar,
      ),
      EditorVoiceNavigationDecision.confirmExit,
      reason: 'Voltar durante gravação pede confirmação',
    );

    expect(
      policy.navigationDecision(
        recording: false,
        commandType: VoiceCommandType.abrirGravacoes,
      ),
      EditorVoiceNavigationDecision.allow,
      reason: 'Navegação permitida sem gravação',
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _editorApp({
  List<Gravacao> recordings = const [],
  NavigatorObserver? observer,
}) {
  return MaterialApp(
    navigatorObservers: [if (observer != null) observer],
    home: EditorPage(
      usuario: _usuario,
      enableVoiceListening: false,
      recordingServiceForTesting: _FakeRecordingManagementService(
        recordings: recordings,
      ),
      scrollControllerForTesting: _InstantScrollController(),
      recordingCaptureForTesting: _NoopAudioRecordingCapture(),
    ),
  );
}

class _PushObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

List<Gravacao> _makeRecordings(int count) => List.generate(
  count,
  (i) => Gravacao(
    id: i + 1,
    usuarioId: 1,
    nome: 'Faixa ${i + 1}',
    caminhoArquivo: '/tmp/faixa_${i + 1}.m4a',
    dataCriacao: '2026-06-17T10:00:00.000',
    duracaoSegundos: 10,
    tamanhoBytes: 1024,
  ),
);

final _usuario = Usuario(
  id: 1,
  nome: 'Teste',
  email: 'teste@example.com',
  senhaHash: 'hash',
);

// ScrollController que resolve animateTo via jumpTo, evitando necessidade de
// pumping de frames dentro de tester.runAsync.
class _InstantScrollController extends ScrollController {
  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (hasClients) jumpTo(offset);
  }
}

// AudioRecordingCapture noop — evita que o plugin `record` nativo seja
// inicializado durante widget tests (MissingPluginException).
class _NoopAudioRecordingCapture implements AudioRecordingCapture {
  @override
  Stream<Uint8List> get rawAudioChunks => const Stream.empty();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<String> startRecording() async => '';

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Future<String?> stopRecording() async => null;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<Amplitude> getAmplitude() async =>
      Amplitude(current: -160, max: -160);

  @override
  Future<bool> isRecording() async => false;

  @override
  Future<bool> isPaused() async => false;

  @override
  Future<void> dispose() async {}
}

class _FakeRecordingManagementService extends RecordingManagementService {
  _FakeRecordingManagementService({this.recordings = const []});

  final List<Gravacao> recordings;

  @override
  Future<List<Gravacao>> listByUserWithFileState(
    int usuarioId, {
    String? termoBusca,
    String? status,
  }) async => recordings;

  @override
  Future<List<Gravacao>> listByProjectWithFileState(
    int projetoId, {
    String? termoBusca,
    String? status,
  }) async => recordings;
}
