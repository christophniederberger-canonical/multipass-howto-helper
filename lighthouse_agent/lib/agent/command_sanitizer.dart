/// Result of a command safety check.
final class SanitizerResult {
  const SanitizerResult({required this.isSafe, this.reason});

  final bool isSafe;
  final String? reason;
}

/// Validates commands before they are passed to multipass exec.
class CommandSanitizer {
  const CommandSanitizer();

  /// Returns [SanitizerResult] indicating whether [command] is safe to execute.
  ///
  /// Day 1 stub — always returns safe. Day 6 will implement the full blocklist.
  SanitizerResult check(String command) {
    return const SanitizerResult(isSafe: true);
  }
}
