import 'package:app_voz/database/app_database.dart';
import 'package:app_voz/features/editor/pages/editor_page.dart';
import 'package:app_voz/features/voices/realtime/runtime/voice_realtime_ecosystem.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/repository_test_utils.dart';

void main() {
  const databaseName = 'editor_page_lifecycle_test.db';

  setUpAll(() {
    configureRepositoryTestDatabase();
  });

  setUp(() async {
    await resetRepositoryTestDatabase(databaseName);
    VoiceRealtimeEcosystem.instance.clearActiveContext();
  });

  tearDown(() async {
    VoiceRealtimeEcosystem.instance.clearActiveContext();
    await resetRepositoryTestDatabase(databaseName);
  });

  testWidgets('EditorPage invalida contexto ao pausar e revalida ao retomar', (
    tester,
  ) async {
    final usuario = Usuario(
      id: 7,
      nome: 'Alex',
      email: 'alex@example.com',
      senhaHash: 'hash',
    );
    final projeto = Projeto(
      id: 9,
      usuarioId: 7,
      nome: 'Projeto Realtime',
      dataCriacao: DateTime(2026, 5, 25).toIso8601String(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(usuario: usuario, projeto: projeto),
      ),
    );
    await tester.pump();

    final holder = VoiceRealtimeEcosystem.instance.sessionContextHolder;
    final initialToken = holder.activeSessionToken;
    expect(holder.currentProjectId, '9');
    expect(holder.currentUserId, '7');
    expect(initialToken, isNotNull);
    expect(VoiceRealtimeEcosystem.instance.activeSessionToken, initialToken);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(holder.currentProjectId, isNull);
    expect(holder.currentUserId, isNull);
    expect(holder.activeSessionToken, isNull);
    expect(VoiceRealtimeEcosystem.instance.activeSessionToken, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(holder.currentProjectId, '9');
    expect(holder.currentUserId, '7');
    expect(holder.activeSessionToken, initialToken);
    expect(VoiceRealtimeEcosystem.instance.activeSessionToken, initialToken);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(holder.currentProjectId, isNull);
    expect(holder.currentUserId, isNull);
    expect(holder.activeSessionToken, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await AppDatabase.instance.close();
  });
}
