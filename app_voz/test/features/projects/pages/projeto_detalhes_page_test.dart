import 'package:app_voz/features/projects/pages/projeto_detalhes_page.dart';
import 'package:app_voz/features/recordings/controllers/recordings_list_controller.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_confirmation_controller.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abrir editor por voz usa o projeto atual', (tester) async {
    final projeto = Projeto(
      id: 42,
      usuarioId: 7,
      nome: 'Demo TCC',
      descricao: 'Projeto da apresentacao',
      dataCriacao: '2026-06-17T10:00:00.000',
    );
    Projeto? projetoAberto;

    await tester.pumpWidget(
      MaterialApp(
        home: ProjetoDetalhesPage(
          usuario: _usuario,
          projeto: projeto,
          recordingsController: _FakeRecordingsListController(),
          enableVoiceListening: false,
          onOpenEditorForTesting: (currentProject) {
            projetoAberto = currentProject;
          },
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;
    final result =
        await state.debugHandleVoiceCommandForTesting('abrir editor')
            as VoiceCommandPageResult;
    await tester.pump();

    expect(result.handled, isTrue);
    expect(result.restartListening, isFalse);
    expect(projetoAberto, same(projeto));
  });

  testWidgets(
    'renomear gravacao por voz no projeto abre modal com nome pre-preenchido',
    (tester) async {
      final gravacao = Gravacao(
        id: 10,
        usuarioId: 7,
        nome: 'Refrao',
        caminhoArquivo: '/tmp/refrao.m4a',
        dataCriacao: '2026-06-17T10:00:00.000',
        duracaoSegundos: 5,
        tamanhoBytes: 256,
      );
      final controller = _FakeRecordingsListController(
        recordings: [gravacao],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProjetoDetalhesPage(
            usuario: _usuario,
            projeto: _projeto,
            recordingsController: controller,
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;

      final resultFuture = (state.debugHandleVoiceCommandForTesting(
            'renomear gravacao refrao para guitarra',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear gravação'), findsOneWidget,
          reason: 'Modal de renomeação deve abrir');
      expect(find.text('guitarra'), findsOneWidget,
          reason: 'Campo deve estar pré-preenchido');

      expect(
        (state.voiceConfirmationController as VoiceConfirmationController)
            .hasPendingConfirmation,
        isTrue,
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await resultFuture;
    },
  );

  testWidgets(
    'renomear projeto para guitarra no projeto abre modal de renomear projeto',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjetoDetalhesPage(
            usuario: _usuario,
            projeto: _projeto,
            recordingsController: _FakeRecordingsListController(),
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;

      final resultFuture = (state.debugHandleVoiceCommandForTesting(
            'renomear projeto para guitarra',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear projeto'), findsOneWidget,
          reason: 'Modal de renomeação de projeto deve abrir');
      expect(find.text('guitarra'), findsOneWidget,
          reason: 'Campo deve estar pré-preenchido com o novo nome');

      expect(
        (state.voiceConfirmationController as VoiceConfirmationController)
            .hasPendingConfirmation,
        isTrue,
        reason: 'Confirmação por voz deve bloquear outros comandos',
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await resultFuture;
    },
  );

  testWidgets(
    'renomear projeto bloqueia reproducao enquanto modal aberto',
    (tester) async {
      final gravacao = Gravacao(
        id: 1,
        usuarioId: 7,
        nome: 'Ideia',
        caminhoArquivo: '/tmp/ideia.m4a',
        dataCriacao: '2026-06-17T10:00:00.000',
        duracaoSegundos: 3,
        tamanhoBytes: 128,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProjetoDetalhesPage(
            usuario: _usuario,
            projeto: _projeto,
            recordingsController: _FakeRecordingsListController(
              recordings: [gravacao],
            ),
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;

      final resultFuture = (state.debugHandleVoiceCommandForTesting(
            'renomear projeto para guitarra',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear projeto'), findsOneWidget);

      // Enquanto modal aberto, reproduzir deve ser bloqueado
      final blockResult =
          await (state.voiceConfirmationController
                  as VoiceConfirmationController)
              .handle(const CommandResult(
        originalText: 'reproduzir gravacao ideia',
        normalizedText: 'reproduzir gravacao ideia',
        type: VoiceCommandType.reproduzirGravacao,
        recognized: true,
        tipoComando: 'reproduzirGravacao',
        parametro: 'ideia',
      ));
      expect(blockResult.action, VoiceConfirmationAction.blocked);

      // Cancela para cleanup
      await (state.voiceConfirmationController
              as VoiceConfirmationController)
          .handle(const CommandResult(
        originalText: 'cancelar',
        normalizedText: 'cancelar',
        type: VoiceCommandType.cancelarAcao,
        recognized: true,
        tipoComando: 'cancelarAcao',
      ));
      await tester.pumpAndSettle();
      await resultFuture;
    },
  );

  testWidgets(
    'frase incompleta renomear projeto nao abre modal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjetoDetalhesPage(
            usuario: _usuario,
            projeto: _projeto,
            recordingsController: _FakeRecordingsListController(),
            enableVoiceListening: false,
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(ProjetoDetalhesPage)) as dynamic;

      // "renomear projeto" sozinho (sem novo nome) → não abre modal
      final result = await (state.debugHandleVoiceCommandForTesting(
            'renomear projeto',
          ) as Future<VoiceCommandPageResult>);
      await tester.pump();

      expect(find.text('Renomear projeto'), findsNothing);
      expect(result.handled, isTrue);
    },
  );
}

final _usuario = Usuario(
  id: 7,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);

final _projeto = Projeto(
  id: 42,
  usuarioId: 7,
  nome: 'Demo TCC',
  descricao: 'Projeto da apresentacao',
  dataCriacao: '2026-06-17T10:00:00.000',
);

class _FakeRecordingsListController extends RecordingsListController {
  _FakeRecordingsListController({List<Gravacao> recordings = const []})
    : _recordings = List.unmodifiable(recordings),
      _state = RecordingsListState(
        loading: false,
        error: null,
        recordings: recordings,
        playingRecordingId: null,
        pendingDeletion: null,
        searchTerm: '',
      );

  final List<Gravacao> _recordings;
  final RecordingsListState _state;

  @override
  RecordingsListState get state => _state;

  @override
  Gravacao? findByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final norm = name.toLowerCase().trim();
    for (final g in _recordings) {
      if (g.nome.toLowerCase().contains(norm)) return g;
    }
    return null;
  }

  @override
  Future<void> loadByProject({required int? projetoId, String? searchTerm}) {
    return Future<void>.value();
  }
}
