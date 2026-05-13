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
  /// Implements a blocklist of dangerous commands and patterns.
  SanitizerResult check(String command) {
    // Normalize the command by trimming whitespace
    final normalizedCommand = command.trim();
    
    if (normalizedCommand.isEmpty) {
      return const SanitizerResult(
        isSafe: false,
        reason: 'Empty command is not allowed',
      );
    }

    // Blocklist from engineering plan.
    const blockedCommands = {
      'mount',
      'umount',
      'mkfs',
      'fdisk',
      'modprobe',
      'insmod',
    };

    for (final blocked in blockedCommands) {
      final pattern = RegExp(
        '(^|\\s|[;&|])' + RegExp.escape(blocked) + r'($|\s|[;&|])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(normalizedCommand)) {
        return SanitizerResult(
          isSafe: false,
          reason: 'Command contains blocked pattern: $blocked',
        );
      }
    }

    const blockedPathPatterns = {
      '/proc/',
      '/sys/',
      '/dev/',
      '--host',
    };
    for (final blocked in blockedPathPatterns) {
      if (normalizedCommand.toLowerCase().contains(blocked.toLowerCase())) {
        return SanitizerResult(
          isSafe: false,
          reason: 'Command contains blocked pattern: $blocked',
        );
      }
    }

    // Check for path traversal attempts
    if (normalizedCommand.contains('../../') || normalizedCommand.contains('..\\..\\')) {
      return const SanitizerResult(
        isSafe: false,
        reason: 'Command contains path traversal attempt',
      );
    }

    // Check for redirection to sensitive files
    if (normalizedCommand.contains('/etc/') || 
        normalizedCommand.contains('/root/') || 
        normalizedCommand.contains('/home/')) {
      // Allow some safe operations but block direct writes to sensitive files
      if (RegExp(r'>\s*/(etc|root|home)/').hasMatch(normalizedCommand)) {
        return const SanitizerResult(
          isSafe: false,
          reason: 'Command attempts to write to sensitive system directories',
        );
      }
    }

    // Check for command injection patterns
    if (normalizedCommand.contains('|') || 
        normalizedCommand.contains('&&') || 
        normalizedCommand.contains('||') ||
        normalizedCommand.contains(';') ||
        normalizedCommand.contains('\$\\(') ||
        normalizedCommand.contains('`')) {
      // Allow some safe usage but block potentially dangerous combinations
      if (normalizedCommand.startsWith('|') || 
          normalizedCommand.endsWith('|') ||
          RegExp(r'[;&|][;&|]').hasMatch(normalizedCommand)) {
        return const SanitizerResult(
          isSafe: false,
          reason: 'Command contains potentially dangerous shell operators',
        );
      }
    }

    // If all checks pass, the command is considered safe
    return const SanitizerResult(
      isSafe: true,
      reason: 'Command passed all security checks',
    );
  }
}
