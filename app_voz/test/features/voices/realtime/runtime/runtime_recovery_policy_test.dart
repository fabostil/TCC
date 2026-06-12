import 'package:app_voz/features/voices/realtime/runtime/runtime_recovery_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeRecoveryPolicy', () {
    test('respeita limite maximo de tentativas consecutivas', () {
      final policy = RuntimeRecoveryPolicy(maxAttempts: 3);

      expect(policy.shouldAttemptRecovery(), isTrue);
      policy.recordFailure();
      expect(policy.shouldAttemptRecovery(), isTrue);
      policy.recordFailure();
      expect(policy.shouldAttemptRecovery(), isTrue);
      policy.recordFailure();
      expect(policy.shouldAttemptRecovery(), isFalse);
    });

    test('calcula backoff linear incremental', () {
      final policy = RuntimeRecoveryPolicy(
        maxAttempts: 3,
        baseBackoff: const Duration(milliseconds: 500),
      );

      expect(policy.nextBackoff(), const Duration(milliseconds: 500));
      policy.recordFailure();
      expect(policy.nextBackoff(), const Duration(milliseconds: 1000));
      policy.recordFailure();
      expect(policy.nextBackoff(), const Duration(milliseconds: 1500));
    });

    test('calcula backoff exponencial incremental', () {
      final policy = RuntimeRecoveryPolicy(
        maxAttempts: 4,
        baseBackoff: const Duration(milliseconds: 250),
        strategy: RuntimeRecoveryBackoffStrategy.exponential,
      );

      expect(policy.nextBackoff(), const Duration(milliseconds: 250));
      policy.recordFailure();
      expect(policy.nextBackoff(), const Duration(milliseconds: 500));
      policy.recordFailure();
      expect(policy.nextBackoff(), const Duration(milliseconds: 1000));
    });

    test('reset limpa falhas consecutivas e reinicia backoff', () {
      final policy = RuntimeRecoveryPolicy(
        maxAttempts: 1,
        baseBackoff: const Duration(seconds: 1),
      );

      policy.recordFailure();
      expect(policy.shouldAttemptRecovery(), isFalse);

      policy.reset();

      expect(policy.consecutiveFailures, 0);
      expect(policy.shouldAttemptRecovery(), isTrue);
      expect(policy.nextBackoff(), const Duration(seconds: 1));
    });
  });
}
