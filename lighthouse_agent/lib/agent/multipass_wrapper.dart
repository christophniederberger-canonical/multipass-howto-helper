import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CommandOutput {
  const CommandOutput({required this.stream, required this.data});

  final String stream;
  final String data;
}

class ExecResult {
  const ExecResult({required this.exitCode});

  final int exitCode;
}

class InteractiveExecSession {
  InteractiveExecSession({
    required Process process,
    required this.output,
    required this.exitCode,
  }) : _process = process;

  final Process _process;
  final Stream<CommandOutput> output;
  final Future<int> exitCode;

  void sendInput(String data) {
    _process.stdin.write(data);
  }

  Future<void> closeInput() {
    return _process.stdin.close();
  }

  void terminate() {
    _process.kill();
  }
}

/// Wraps the Multipass CLI to manage VM lifecycle.
///
/// All operations are async and communicate via `Process.run` / `Process.start`.
/// The [exec] method returns a stream of [CommandOutput] events followed by
/// a single [ExecResult] containing the exit code.
///
/// For testing, optional [processRun] and [processStart] functions can be
/// injected to mock process behavior.
class MultipassWrapper {
  const MultipassWrapper({
    this.processRun = Process.run,
    this.processStart = Process.start,
  });

  final Future<ProcessResult> Function(String, List<String>) processRun;
  final Future<Process> Function(String, List<String>) processStart;

  /// Detects whether `multipass` is available in PATH.
  Future<bool> isAvailable() async {
    try {
      final result = await processRun('which', const <String>['multipass']);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Launches a new VM with the given name.
  ///
  /// Runs `multipass launch --name <vmName> 24.04 -c 2 -m 2G -d 10G` and waits
  /// for completion. Uses Ubuntu 24.04 with 2 CPUs, 2GB RAM, and 10GB disk.
  /// Returns the VM name on success.
  /// Throws if multipass is unavailable or launch fails.
  Future<String> launch({required String vmName, int maxRetries = 3}) async {
    Exception? lastError;
    
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final result = await processRun(
          'multipass',
          <String>[
            'launch',
            '--name', vmName,
            '24.04',
            '-c', '2',
            '-m', '2G',
            '-d', '10G',
          ],
        );

        if (result.exitCode == 0) {
          return vmName;
        }

        final stderrText = (result.stderr as String).trim();
        lastError = Exception('multipass launch failed: $stderrText');
        
        // Check if error is retriable
        final errorStr = stderrText.toLowerCase();
        if (errorStr.contains('daemon') || 
            errorStr.contains('timeout') ||
            errorStr.contains('busy')) {
          // Exponential backoff: 1s, 2s, 4s
          final delay = Duration(seconds: 1 << attempt);
          await Future.delayed(delay);
          continue;
        }
        
        // Non-retriable error, throw immediately
        throw lastError;
      } on Object catch (e) {
        lastError = Exception('multipass launch error: $e');
        if (attempt < maxRetries - 1) {
          final delay = Duration(seconds: 1 << attempt);
          await Future.delayed(delay);
          continue;
        }
      }
    }
    
    throw lastError ?? Exception('multipass launch failed after $maxRetries attempts');
  }

  /// Executes a command inside a VM and streams stdout/stderr in real time.
  ///
  /// Runs `multipass exec <vmName> -- bash -c '<command>'` using [Process.start]
  /// so that stdout and stderr are available as streams.
  ///
  /// Yields [CommandOutput] events for each line of stdout/stderr, then yields
  /// a final [ExecResult] with the exit code.
  Stream<Object> exec({
    required String vmName,
    required String command,
  }) async* {
    final process = await processStart(
      'multipass',
      <String>['exec', vmName, '--', 'bash', '-c', command],
    );

    try {
      // Merge stdout and stderr into a single stream of CommandOutput events.
      await for (final event in _mergeStreams(process.stdout, process.stderr)) {
        yield event;
      }

      final exitCode = await process.exitCode;
      yield ExecResult(exitCode: exitCode);
    } finally {
      // Ensure the process is killed if the stream is cancelled or errors.
      process.kill();
    }
  }

  /// Starts an interactive command execution and returns handles for output,
  /// exit code, and stdin forwarding.
  Future<InteractiveExecSession> startInteractiveExec({
    required String vmName,
    required String command,
  }) async {
    final process = await processStart(
      'multipass',
      <String>['exec', vmName, '--', 'bash', '-c', command],
    );

    final output = _mergeChunkStreams(process.stdout, process.stderr);
    return InteractiveExecSession(
      process: process,
      output: output,
      exitCode: process.exitCode,
    );
  }

  /// Merges [stdout] and [stderr] byte streams into [CommandOutput] events.
  Stream<CommandOutput> _mergeStreams(
    Stream<List<int>> stdout,
    Stream<List<int>> stderr,
  ) {
    final controller = StreamController<CommandOutput>();
    var pending = 2;
    StreamSubscription<void>? stdoutSub;
    StreamSubscription<void>? stderrSub;

    void onDone() {
      pending--;
      if (pending == 0 && !controller.isClosed) {
        controller.close();
      }
    }

    void onError(Object error, StackTrace stackTrace) {
      // Cancel the other subscription and close with error.
      stdoutSub?.cancel();
      stderrSub?.cancel();
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        controller.close();
      }
    }

    stdoutSub = stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => controller.add(CommandOutput(stream: 'stdout', data: line)),
          onDone: onDone,
          onError: onError,
        );

    stderrSub = stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => controller.add(CommandOutput(stream: 'stderr', data: line)),
          onDone: onDone,
          onError: onError,
        );

    return controller.stream;
  }

  Stream<CommandOutput> _mergeChunkStreams(
    Stream<List<int>> stdout,
    Stream<List<int>> stderr,
  ) {
    final controller = StreamController<CommandOutput>();
    var pending = 2;
    StreamSubscription<void>? stdoutSub;
    StreamSubscription<void>? stderrSub;

    void onDone() {
      pending--;
      if (pending == 0 && !controller.isClosed) {
        controller.close();
      }
    }

    void onError(Object error, StackTrace stackTrace) {
      stdoutSub?.cancel();
      stderrSub?.cancel();
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        controller.close();
      }
    }

    stdoutSub = stdout
        .transform(utf8.decoder)
        .listen(
          (chunk) => controller.add(CommandOutput(stream: 'stdout', data: chunk)),
          onDone: onDone,
          onError: onError,
        );

    stderrSub = stderr
        .transform(utf8.decoder)
        .listen(
          (chunk) => controller.add(CommandOutput(stream: 'stderr', data: chunk)),
          onDone: onDone,
          onError: onError,
        );

    return controller.stream;
  }

  /// Deletes (and purges) a VM.
  ///
  /// Runs `multipass delete --purge <vmName>`.
  /// Does not throw if the VM is already gone.
  /// Throws [Exception] for other failures (disk full, permission denied, etc.).
  Future<void> delete({required String vmName, bool purge = true}) async {
    final args = purge
        ? <String>['delete', '--purge', vmName]
        : <String>['delete', vmName];

    final result = await processRun('multipass', args);

    if (result.exitCode != 0) {
      final stderrText = (result.stderr as String).toLowerCase();
      // Gracefully handle "already deleted" or "does not exist" cases.
      if (stderrText.contains('does not exist') ||
          stderrText.contains('unknown') ||
          stderrText.contains('not found')) {
        return;
      }

      // For other errors, throw so the caller can handle them.
      throw Exception(
        'multipass delete failed for $vmName: ${(result.stderr as String).trim()}',
      );
    }
  }

  /// Gets information about a VM including status, memory, disk usage.
  ///
  /// Runs `multipass info <vmName>` and parses the output.
  /// Returns null if the VM doesn't exist.
  Future<VmInfo?> info({required String vmName}) async {
    final result = await processRun(
      'multipass',
      <String>['info', vmName],
    );

    if (result.exitCode != 0) {
      final stderrText = (result.stderr as String).toLowerCase();
      if (stderrText.contains('does not exist') ||
          stderrText.contains('unknown') ||
          stderrText.contains('not found')) {
        return null;
      }
      throw Exception('multipass info failed: ${(result.stderr as String).trim()}');
    }

    return _parseInfoOutput(result.stdout as String, vmName);
  }

  /// Gets a list of all VMs.
  ///
  /// Runs `multipass list` and parses the output.
  Future<List<VmListEntry>> list() async {
    final result = await processRun('multipass', <String>['list']);

    if (result.exitCode != 0) {
      // If multipass returns error, return empty list
      return [];
    }

    return _parseListOutput(result.stdout as String);
  }

  /// Parses the output of `multipass info <vmName>`.
  VmInfo? _parseInfoOutput(String output, String vmName) {
    // Parse output like:
    // Name:           lighthouse-abc123
    // State:          Running
    // ...
    final lines = output.split('\n');
    String? state;
    int? cpuCount;
    String? memory;
    String? disk;
    String? ipv4;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('State:')) {
        state = trimmed.substring(6).trim().toLowerCase();
      } else if (trimmed.startsWith('CPU(s):')) {
        cpuCount = int.tryParse(trimmed.substring(7).trim());
      } else if (trimmed.startsWith('Memory:')) {
        memory = trimmed.substring(7).trim();
      } else if (trimmed.startsWith('Disk:')) {
        disk = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('IPv4:')) {
        ipv4 = trimmed.substring(5).trim();
      }
    }

    if (state == null) return null;

    return VmInfo(
      name: vmName,
      state: state,
      cpuCount: cpuCount,
      memory: memory,
      disk: disk,
      ipv4: ipv4,
    );
  }

  /// Parses the output of `multipass list`.
  List<VmListEntry> _parseListOutput(String output) {
    final entries = <VmListEntry>[];
    final lines = output.split('\n');

    // Skip header line
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Format: "Name                    State    IPv4            ..." 
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        entries.add(VmListEntry(
          name: parts[0],
          state: parts[1].toLowerCase(),
        ));
      }
    }

    return entries;
  }
}

class VmInfo {
  const VmInfo({
    required this.name,
    required this.state,
    this.cpuCount,
    this.memory,
    this.disk,
    this.ipv4,
  });

  final String name;
  final String state;
  final int? cpuCount;
  final String? memory;
  final String? disk;
  final String? ipv4;

  bool get isRunning => state == 'running';
  bool get isStopped => state == 'stopped';
  bool get isStarting => state == 'starting';
}

class VmListEntry {
  const VmListEntry({
    required this.name,
    required this.state,
  });

  final String name;
  final String state;
}
