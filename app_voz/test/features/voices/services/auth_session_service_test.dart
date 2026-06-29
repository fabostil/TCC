import 'dart:io';

import 'package:app_voz/features/voices/services/auth_session_service.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stopStep = 'stopActiveVoiceSession';
  const clearContextStep = 'clearActiveVoiceContext';
  const clearRuntimeStep = 'clearRuntimeVoiceSession';
  const clearPersistedStep = 'clearPersistedSession';
  const googleStep = 'googleSignOut';

  AuthSessionService serviceWithOrder(
    List<String> calls, {
    Object? failingStepError,
    String? failingStep,
  }) {
    Future<void> runAsyncStep(String step) async {
      calls.add(step);
      if (failingStep == step) {
        throw failingStepError ?? StateError('$step failed');
      }
    }

    void runSyncStep(String step) {
      calls.add(step);
      if (failingStep == step) {
        throw failingStepError ?? StateError('$step failed');
      }
    }

    Future<String> sessionDirectoryPathProvider() async {
      calls.add(clearPersistedStep);
      if (failingStep == clearPersistedStep) {
        throw failingStepError ?? StateError('$clearPersistedStep failed');
      }
      return Directory.systemTemp
          .createTempSync('auth_session_logout_test')
          .path;
    }

    return AuthSessionService(
      stopActiveVoiceSession: () => runAsyncStep(stopStep),
      clearActiveVoiceContext: () => runSyncStep(clearContextStep),
      clearRuntimeVoiceSession: () => runSyncStep(clearRuntimeStep),
      sessionDirectoryPathProvider: sessionDirectoryPathProvider,
      googleSignOut: () => runAsyncStep(googleStep),
    );
  }

  group('AuthSessionService', () {
    test('logout chama etapas na ordem correta', () async {
      final calls = <String>[];

      await serviceWithOrder(calls).logout();

      expect(calls, [
        stopStep,
        clearContextStep,
        clearRuntimeStep,
        clearPersistedStep,
        googleStep,
      ]);
    });

    test('logout sem falhas completa sem lancar excecao', () async {
      final calls = <String>[];

      await expectLater(serviceWithOrder(calls).logout(), completes);
    });

    test(
      'logout continua executando os passos quando stopActiveVoiceSession falha',
      () async {
        final calls = <String>[];

        await expectLater(
          serviceWithOrder(calls, failingStep: stopStep).logout(),
          throwsA(isA<AuthSessionLogoutException>()),
        );

        expect(calls, [
          stopStep,
          clearContextStep,
          clearRuntimeStep,
          clearPersistedStep,
          googleStep,
        ]);
      },
    );

    test(
      'logout continua executando os passos quando clearActiveVoiceContext falha',
      () async {
        final calls = <String>[];

        await expectLater(
          serviceWithOrder(calls, failingStep: clearContextStep).logout(),
          throwsA(isA<AuthSessionLogoutException>()),
        );

        expect(calls, [
          stopStep,
          clearContextStep,
          clearRuntimeStep,
          clearPersistedStep,
          googleStep,
        ]);
      },
    );

    test(
      'logout continua executando os passos quando clearRuntimeVoiceSession falha',
      () async {
        final calls = <String>[];

        await expectLater(
          serviceWithOrder(calls, failingStep: clearRuntimeStep).logout(),
          throwsA(isA<AuthSessionLogoutException>()),
        );

        expect(calls, [
          stopStep,
          clearContextStep,
          clearRuntimeStep,
          clearPersistedStep,
          googleStep,
        ]);
      },
    );

    test(
      'logout continua executando os passos quando googleSignOut falha',
      () async {
        final calls = <String>[];

        await expectLater(
          serviceWithOrder(calls, failingStep: googleStep).logout(),
          throwsA(isA<AuthSessionLogoutException>()),
        );

        expect(calls, [
          stopStep,
          clearContextStep,
          clearRuntimeStep,
          clearPersistedStep,
          googleStep,
        ]);
      },
    );

    test(
      'logout continua executando googleSignOut quando limpar sessao falha',
      () async {
        final calls = <String>[];

        await expectLater(
          serviceWithOrder(calls, failingStep: clearPersistedStep).logout(),
          throwsA(isA<AuthSessionLogoutException>()),
        );

        expect(calls, [
          stopStep,
          clearContextStep,
          clearRuntimeStep,
          clearPersistedStep,
          googleStep,
        ]);
      },
    );

    test('AuthSessionLogoutException preserva primeira falha', () async {
      final calls = <String>[];
      final originalError = StateError('first failure');

      try {
        await serviceWithOrder(
          calls,
          failingStep: clearContextStep,
          failingStepError: originalError,
        ).logout();
        fail('logout deveria lancar AuthSessionLogoutException');
      } on AuthSessionLogoutException catch (error) {
        expect(error.failedStep, clearContextStep);
        expect(error.originalError, same(originalError));
        expect(error.originalStackTrace, isA<StackTrace>());
      }
    });

    test('AuthSessionLogoutException ignora falhas posteriores', () async {
      final calls = <String>[];
      final firstError = StateError('first failure');
      final secondError = StateError('second failure');
      final service = AuthSessionService(
        stopActiveVoiceSession: () async {
          calls.add(stopStep);
          throw firstError;
        },
        clearActiveVoiceContext: () {
          calls.add(clearContextStep);
        },
        clearRuntimeVoiceSession: () {
          calls.add(clearRuntimeStep);
          throw secondError;
        },
        sessionDirectoryPathProvider: () async => Directory.systemTemp
            .createTempSync('auth_session_failure_test')
            .path,
        googleSignOut: () async {
          calls.add(googleStep);
        },
      );

      try {
        await service.logout();
        fail('logout deveria lancar AuthSessionLogoutException');
      } on AuthSessionLogoutException catch (error) {
        expect(error.failedStep, stopStep);
        expect(error.originalError, same(firstError));
      }

      expect(calls, [stopStep, clearContextStep, clearRuntimeStep, googleStep]);
    });

    test('salva sessao com usuario_id e restaura usuario valido', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_session_restore_valid',
      );
      final usuario = _usuario(id: 7);
      final service = AuthSessionService(
        sessionDirectoryPathProvider: () async => directory.path,
        userById: (id) async => id == 7 ? usuario : null,
      );

      await service.saveAuthenticatedUser(usuario);
      final restored = await service.restoreAuthenticatedUser();

      expect(restored, same(usuario));
      final files = directory.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final persisted = await files.single.readAsString();
      expect(persisted, '7');
      expect(persisted, isNot(contains('senha')));
      expect(persisted, isNot(contains('token')));
      expect(persisted, isNot(contains('hash')));
    });

    test('limpa sessao persistida', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_session_clear',
      );
      final service = AuthSessionService(
        sessionDirectoryPathProvider: () async => directory.path,
      );

      await service.saveAuthenticatedUser(_usuario(id: 3));
      await service.clearPersistedSession();

      expect(await service.restoreAuthenticatedUser(), isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
    });

    test('logout limpa sessao persistida', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_session_logout_clear',
      );
      final service = AuthSessionService(
        stopActiveVoiceSession: () async {},
        clearActiveVoiceContext: () {},
        clearRuntimeVoiceSession: () {},
        googleSignOut: () async {},
        sessionDirectoryPathProvider: () async => directory.path,
      );

      await service.saveAuthenticatedUser(_usuario(id: 3));
      await service.logout();

      expect(await service.restoreAuthenticatedUser(), isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
    });

    test('sessao invalida e tratada como ausente e removida', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_session_invalid',
      );
      final service = AuthSessionService(
        sessionDirectoryPathProvider: () async => directory.path,
        userById: (_) async => null,
      );

      await service.saveAuthenticatedUser(_usuario(id: 99));
      final restored = await service.restoreAuthenticatedUser();

      expect(restored, isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
    });

    test('usuario sem id nao cria sessao persistida', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_session_no_id',
      );
      final service = AuthSessionService(
        sessionDirectoryPathProvider: () async => directory.path,
      );

      await service.saveAuthenticatedUser(_usuario(id: null));

      expect(directory.listSync().whereType<File>(), isEmpty);
    });

    test('AuthSessionLogoutException possui toString tecnico em ingles', () {
      final originalError = StateError('google failed');
      final exception = AuthSessionLogoutException(
        failedStep: googleStep,
        originalError: originalError,
        originalStackTrace: StackTrace.current,
      );

      expect(
        exception.toString(),
        contains('AuthSessionLogoutException(step: googleSignOut, error:'),
      );
    });
  });
}

Usuario _usuario({required int? id}) {
  return Usuario(
    id: id,
    nome: 'Ana',
    email: 'ana@example.com',
    senhaHash: 'hash-nao-persistido',
  );
}
