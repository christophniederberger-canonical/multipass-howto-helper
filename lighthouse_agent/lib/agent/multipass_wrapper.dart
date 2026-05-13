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
  static Future<bool> isAvailable() async {
    try {
      final result = await Process.run('which', const <String>['multipass']);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Launches a new VM with the given name.
  ///
  /// Runs `multipass launch --name <vmName>` and waits for completion.
  /// Returns the VM name on success.
  /// Throws if multipass is unavailable or launch fails.
  Future<String> launch({required String vmName}) async {
    final result = await processRun(
      'multipass',
      <String>['launch', '--name', vmName],
    );

    if (result.exitCode != 0) {
      final stderrText = (result.stderr as String).trim();
      throw Exception('multipass launch failed: $stderrText');
    }

    return vmName;
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

    // Merge stdout and stderr into a single stream of CommandOutput events.
    await for (final event in _mergeStreams(process.stdout, process.stderr)) {
      yield event;
    }

    final exitCode = await process.exitCode;
    yield ExecResult(exitCode: exitCode);
  }

  /// Merges [stdout] and [stderr] byte streams into [CommandOutput] events.
  Stream<CommandOutput> _mergeStreams(
    Stream<List<int>> stdout,
    Stream<List<int>> stderr,
  ) {
    final controller = StreamController<CommandOutput>();
    var pending = 2;

    void onDone() {
      pending--;
      if (pending == 0 && !controller.isClosed) {
        controller.close();
      }
    }

    stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => controller.add(CommandOutput(stream: 'stdout', data: line)),
          onDone: onDone,
          onError: (Object error) => controller.addError(error),
        );

    stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => controller.add(CommandOutput(stream: 'stderr', data: line)),
          onDone: onDone,
          onError: (Object error) => controller.addError(error),
        );

    return controller.stream;
  }

  /// Deletes (and purges) a VM.
  ///
  /// Runs `multipass delete --purge <vmName>`.
  /// Does not throw if the VM is already gone.
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
        stdout.writeln('VM $vmName already deleted or does not exist; ignoring.');
        return;
      }

      // For other errors, log a warning but do not throw.
      stderr.writeln(
        'Warning: multipass delete failed for $vmName: ${result.stderr}',
      );
    }
  }
}
