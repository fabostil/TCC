import 'package:app_voz/features/voices/services/auth_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stopStep = 'stopActiveVoiceSession';
  const clearContextStep = 'clearActiveVoiceContext';
  const clearRuntimeStep = 'clearRuntimeVoiceSession';
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

    return AuthSessionService(
      stopActiveVoiceSession: () => runAsyncStep(stopStep),
      clearActiveVoiceContext: () => runSyncStep(clearContextStep),
      clearRuntimeVoiceSession: () => runSyncStep(clearRuntimeStep),
      googleSignOut: () => runAsyncStep(googleStep),
    );
  }

  group('AuthSessionService', () {
    test('logout chama etapas na ordem correta', () async {
      final calls = <String>[];

      await serviceWithOrder(calls).logout();

      expect(calls, [stopStep, clearContextStep, clearRuntimeStep, googleStep]);
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
