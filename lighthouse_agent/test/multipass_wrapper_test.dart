import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse_agent/agent/multipass_wrapper.dart';

class _FakeProcess implements Process {
  _FakeProcess({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  final Future<int> exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MultipassWrapper', () {
    group('launch', () {
      test('returns vmName on success', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 0, '', '');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        final result = await wrapper.launch(vmName: 'lighthouse-abc123');
        expect(result, 'lighthouse-abc123');
      });

      test('throws on non-zero exit', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 1, '', 'launch failed: no disk space');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        expect(
          wrapper.launch(vmName: 'lighthouse-abc123'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('launch failed'),
            ),
          ),
        );
      });
    });

    group('exec', () {
      test('streams stdout and stderr then yields ExecResult', () async {
        final stdoutController = StreamController<List<int>>();
        final stderrController = StreamController<List<int>>();
        final exitCodeCompleter = Completer<int>();

        Future<Process> fakeStart(String cmd, List<String> args) async {
          return _FakeProcess(
            stdout: stdoutController.stream,
            stderr: stderrController.stream,
            exitCode: exitCodeCompleter.future,
          );
        }

        final wrapper = MultipassWrapper(processStart: fakeStart);
        final events = <Object>[];
        final done = Completer<void>();
        final sub = wrapper.exec(vmName: 'vm1', command: 'echo hello').listen(
          (event) {
            events.add(event);
            if (event is ExecResult) {
              done.complete();
            }
          },
          onError: (Object e) => events.add(e),
        );

        stdoutController.add(utf8.encode('hello\n'));
        stderrController.add(utf8.encode('warn\n'));
        exitCodeCompleter.complete(0);
        await stdoutController.close();
        await stderrController.close();

        await done.future;
        await sub.cancel();

        expect(events.length, 3);
        expect(events[0], isA<CommandOutput>());
        expect((events[0] as CommandOutput).stream, 'stdout');
        expect((events[0] as CommandOutput).data, 'hello');
        expect(events[1], isA<CommandOutput>());
        expect((events[1] as CommandOutput).stream, 'stderr');
        expect((events[1] as CommandOutput).data, 'warn');
        expect(events[2], isA<ExecResult>());
        expect((events[2] as ExecResult).exitCode, 0);
      });
    });

    group('delete', () {
      test('succeeds on zero exit', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 0, '', '');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        await expectLater(
          wrapper.delete(vmName: 'lighthouse-abc123'),
          completes,
        );
      });

      test('does not throw when VM does not exist', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 1, '', 'error: vm "lighthouse-abc123" does not exist');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        await expectLater(
          wrapper.delete(vmName: 'lighthouse-abc123'),
          completes,
        );
      });

      test('throws on unknown stderr', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 1, '', 'some other error');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        expect(
          wrapper.delete(vmName: 'lighthouse-abc123'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('multipass delete failed'),
            ),
          ),
        );
      });
    });

    group('isAvailable', () {
      test('returns true when multipass is in PATH', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 0, '', '');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        final result = await wrapper.isAvailable();
        expect(result, isTrue);
      });

      test('returns false when multipass is not in PATH', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          return ProcessResult(0, 1, '', '');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        final result = await wrapper.isAvailable();
        expect(result, isFalse);
      });

      test('returns false when process throws', () async {
        Future<ProcessResult> fakeRun(String cmd, List<String> args) async {
          throw const FileSystemException('not found');
        }

        final wrapper = MultipassWrapper(processRun: fakeRun);
        final result = await wrapper.isAvailable();
        expect(result, isFalse);
      });
    });
  });
}
