class RuntimeRecoveryPolicy {
  RuntimeRecoveryPolicy({
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(milliseconds: 700),
    this.strategy = RuntimeRecoveryBackoffStrategy.linear,
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration baseBackoff;
  final RuntimeRecoveryBackoffStrategy strategy;

  int _consecutiveFailures = 0;

  int get consecutiveFailures => _consecutiveFailures;

  int get nextAttemptNumber => _consecutiveFailures + 1;

  bool shouldAttemptRecovery() => _consecutiveFailures < maxAttempts;

  Duration nextBackoff() {
    final multiplier = switch (strategy) {
      RuntimeRecoveryBackoffStrategy.linear => nextAttemptNumber,
      RuntimeRecoveryBackoffStrategy.exponential => 1 << _consecutiveFailures,
    };
    return baseBackoff * multiplier;
  }

  void recordFailure() {
    _consecutiveFailures += 1;
  }

  void reset() {
    _consecutiveFailures = 0;
  }
}

enum RuntimeRecoveryBackoffStrategy { linear, exponential }
