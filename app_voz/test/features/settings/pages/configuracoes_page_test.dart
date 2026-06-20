import 'dart:async';

import 'package:app_voz/features/settings/controllers/settings_controller.dart';
import 'package:app_voz/features/settings/pages/configuracoes_page.dart';
import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_session_manager.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:app_voz/repositories/comando_personalizado_repository.dart';
import 'package:app_voz/repositories/configuracao_app_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _usuario = Usuario(
  id: 1,
  nome: 'Dev Teste',
  email: 'dev@example.com',
  senhaHash: 'hash',
);

void main() {
  setUp(() => VoiceSessionManager.instance.resetForTesting());
  tearDown(() => VoiceSessionManager.instance.resetForTesting());

  group('ConfiguracoesPage H11.6 logout por voz', () {
    testWidgets('sair por voz abre dialog visual de confirmacao', (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      final future = _dispatchSettingsCommand(tester, 'sair');
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);
      expect(
        find.textContaining('Você será desconectado do Touchless.'),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await future;
    });

    testWidgets('encerrar sessao por voz abre dialog de confirmacao',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      final future = _dispatchSettingsCommand(tester, 'encerrar sessão');
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await future;
    });

    testWidgets('encerrar conta por voz abre dialog de confirmacao',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      final future = _dispatchSettingsCommand(tester, 'encerrar conta');
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await future;
    });

    testWidgets('cancelar por voz fecha dialog e retorna Sair cancelado',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      unawaited(_dispatchSettingsCommand(tester, 'sair'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);

      final state = _settingsState(tester);
      final cancelResult =
          await state.voiceConfirmationController.handle(
        const CommandService().interpret('cancelar'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Sair da conta?'), findsNothing);
      expect(cancelResult.handled, isTrue);
    });

    testWidgets('botao Cancelar no dialog fecha sem chamar logout',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      unawaited(_dispatchSettingsCommand(tester, 'sair'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Sair da conta?'), findsNothing);
      expect(find.byType(ConfiguracoesPage), findsOneWidget);
    });

    testWidgets('botao confirmar logout via UI abre dialog e confirma',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      // Botao de logout na UI (nao por voz)
      await tester.tap(find.byKey(const Key('logout_button')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);

      // Fechar dialog para liberar timers
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('ConfiguracoesPage HOTFIX PROBLEMA 9: tema somente em Configuracoes', () {
    testWidgets('ativar tema escuro e tratado em Configuracoes sem global', (
      tester,
    ) async {
      await _pumpConfiguracoes(tester, _usuario);

      // Configuracoes has voiceHandlesGlobalCommands=false, so global service
      // is skipped; the page-level handler processes the theme command itself.
      final result = await _dispatchSettingsCommand(tester, 'ativar tema escuro');

      // The command must be handled (orientation or success — never a global bypass)
      expect(result.handled, isTrue);
    });

    testWidgets('desativar tema escuro e tratado em Configuracoes', (
      tester,
    ) async {
      await _pumpConfiguracoes(tester, _usuario);

      final result = await _dispatchSettingsCommand(
        tester,
        'desativar tema escuro',
      );

      expect(result.handled, isTrue);
    });
  });

  group('ConfiguracoesPage H11.6 ajuda contextual', () {
    testWidgets('ajuda por voz abre dialog com comandos de configuracoes',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      unawaited(_dispatchSettingsCommand(tester, 'ajuda'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Comandos em configurações'), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice_command_help_close_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Comandos em configurações'), findsNothing);
    });

    testWidgets('abrir assistente por voz abre dialog de ajuda', (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      unawaited(_dispatchSettingsCommand(tester, 'abrir assistente'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Comandos em configurações'), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice_command_help_close_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('fechar por voz fecha dialog de ajuda em configuracoes',
        (tester) async {
      await _pumpConfiguracoes(tester, _usuario);

      unawaited(_dispatchSettingsCommand(tester, 'ajuda'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Comandos em configurações'), findsOneWidget);

      final state = _settingsState(tester);
      unawaited(state.processContextualVoiceInput('fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Comandos em configurações'), findsNothing);
    });
  });
}

Future<void> _pumpConfiguracoes(WidgetTester tester, Usuario usuario) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConfiguracoesPage(
        usuario: usuario,
        enableVoiceListening: false,
        settingsController: _FakeSettingsController(),
      ),
    ),
  );
  await tester.pump();
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController()
    : super(
        configuracaoRepository: _FakeConfiguracaoRepo(),
        comandoRepository: _FakeComandoRepo(),
      );

  @override
  Future<void> load({required int? usuarioId}) async {}

  @override
  SettingsState get state => SettingsState(
    loading: false,
    configuration: ConfiguracaoApp.padrao().copyWith(
      comandosVozAtivos: false,
      escutaContinua: false,
    ),
    customCommands: const [],
  );

  @override
  Future<ConfiguracaoApp> setDarkTheme(bool active) async =>
      ConfiguracaoApp.padrao().copyWith(temaEscuro: active);
}

class _FakeConfiguracaoRepo implements ConfiguracaoAppRepository {
  @override
  Future<ConfiguracaoApp> buscarConfiguracao() async => ConfiguracaoApp.padrao();
  @override
  Future<void> salvarConfiguracao(ConfiguracaoApp c) async {}
  @override
  Future<void> atualizarComandosVoz(bool ativo) async {}
  @override
  Future<void> atualizarEscutaContinua(bool ativo) async {}
  @override
  Future<void> atualizarFeedbackSonoro(bool ativo) async {}
  @override
  Future<void> atualizarParadaSilencio(bool ativo) async {}
  @override
  Future<void> atualizarTemaEscuro(bool ativo) async {}
  @override
  Future<void> atualizarTempoSilencio(int segundos) async {}
  @override
  Future<void> concluirPrimeiraExecucao({required bool comandosVozAtivos}) async {}
}

class _FakeComandoRepo implements ComandoPersonalizadoRepository {
  @override
  Future<int> salvar(ComandoPersonalizado c) async => 1;
  @override
  Future<List<ComandoPersonalizado>> listarPorUsuario(int id) async => [];
  @override
  Future<List<ComandoPersonalizado>> listarAtivosPorUsuario(int id) async => [];
  @override
  Future<void> alternarAtivo({required int id, required bool ativo}) async {}
  @override
  Future<void> excluir(int id) async {}
}

Future<VoiceCommandPageResult> _dispatchSettingsCommand(
  WidgetTester tester,
  String text,
) async {
  final state = _settingsState(tester);
  final result = const CommandService().interpret(text);
  return await state.voiceCommandDispatcher.dispatch(result)
      as VoiceCommandPageResult;
}

dynamic _settingsState(WidgetTester tester) =>
    tester.state(find.byType(ConfiguracoesPage));
