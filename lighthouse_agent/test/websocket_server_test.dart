import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse_agent/agent/multipass_wrapper.dart';
import 'package:lighthouse_agent/agent/session_manager.dart';
import 'package:lighthouse_agent/agent/websocket_server.dart';
import 'package:lighthouse_agent/models/message.dart';
import 'package:lighthouse_agent/models/session.dart';
import 'package:lighthouse_agent/ui/permission_dialog.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake MultipassWrapper for testing without actual Multipass.
class FakeMultipassWrapper extends MultipassWrapper {
  FakeMultipassWrapper({
    this.launchDelay = const Duration(milliseconds: 50),
    this.execDelay = const Duration(milliseconds: 30),
    this.shouldFailLaunch = false,
    this.execOutputs = const [
      CommandOutput(stream: 'stdout', data: 'Hello from fake VM!'),
      CommandOutput(stream: 'stdout', data: 'Command executed.'),
    ],
    this.execExitCode = 0,
  }) : super(
    processRun: (cmd, args) async => ProcessResult(0, 0, '', ''),
    processStart: (cmd, args) async => throw UnsupportedError('Not used in fake'),
  );

  final Duration launchDelay;
  final Duration execDelay;
  final bool shouldFailLaunch;
  final List<CommandOutput> execOutputs;
  final int execExitCode;
  final List<String> launchedVms = [];
  final List<String> deletedVms = [];

  @override
  Future<String> launch({required String vmName}) async {
    await Future.delayed(launchDelay);
    if (shouldFailLaunch) {
      throw Exception('multipass launch failed: no disk space');
    }
    launchedVms.add(vmName);
    return vmName;
  }

  @override
  Stream<Object> exec({required String vmName, required String command}) async* {
    await Future.delayed(execDelay);
    for (final output in execOutputs) {
      yield output;
    }
    yield ExecResult(exitCode: execExitCode);
  }

  @override
  Future<void> delete({required String vmName, bool purge = true}) async {
    deletedVms.add(vmName);
  }
}

void main() {
  group('WebSocketServer Integration Tests', () {
    late WebSocketServer server;
    late FakeMultipassWrapper fakeMultipass;
    late SessionManager sessionManager;
    int port = 50053; // Use different port to avoid conflicts

    setUp(() {
      fakeMultipass = FakeMultipassWrapper();
      sessionManager = SessionManager();
    });

    tearDown(() async {
      await server.stop();
      // Give time for port to be released
      await Future.delayed(const Duration(milliseconds: 300));
    });

    Future<void> startServer({
      required PermissionDecision autoDecision,
    }) async {
      server = WebSocketServer(
        port: port,
        sessionManager: sessionManager,
        multipass: fakeMultipass,
        onPermissionRequested: (origin) async => autoDecision,
      );
      await server.start();
    }

    Future<WebSocketChannel> connectToServer() async {
      final wsUrl = 'ws://127.0.0.1:$port';
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await Future.delayed(const Duration(milliseconds: 100));
      return channel;
    }

    Future<List<Map<String, dynamic>>> collectMessages(
      WebSocketChannel channel, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final messages = <Map<String, dynamic>>[];
      final doneCompleter = Completer<void>();
      final timer = Timer(timeout, () {
        if (!doneCompleter.isCompleted) {
          doneCompleter.complete();
        }
      });

      channel.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          messages.add(msg);
          // Stop on terminal messages
          if (['exec_done', 'error', 'agent_error', 'session_denied'].contains(msg['type'])) {
            if (!doneCompleter.isCompleted) {
              doneCompleter.complete();
            }
          }
        },
        onDone: () {
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete();
          }
        },
        onError: (error) {
          if (!doneCompleter.isCompleted) {
            doneCompleter.completeError(error);
          }
        },
      );

      await doneCompleter.future;
      timer.cancel();
      return messages;
    }

    void sendMessage(WebSocketChannel channel, LighthouseMessage message) {
      channel.sink.add(const MessageCodec().encode(message));
    }

    group('session_start', () {
      test('valid origin creates pending session without sending session_ready', () async {
        await startServer(autoDecision: PermissionDecision.allow);
        final channel = await connectToServer();

        // Send session_start
        sendMessage(channel, const SessionStart(
          origin: 'http://localhost:8080',
          tutorialUrl: 'http://localhost:8080/test',
        ));

        // Wait a bit to ensure no response is sent
        await Future.delayed(const Duration(seconds: 1));

        // Session should be in pending state
        expect(sessionManager.sessions.length, 1);
        final session = sessionManager.sessions.first;
        expect(session.state, SessionState.pending);

        await channel.sink.close();
      });

      test('invalid origin receives session_denied and connection closes', () async {
        await startServer(autoDecision: PermissionDecision.allow);
        final channel = await connectToServer();

        final closeCompleter = Completer<void>();
        final messages = <Map<String, dynamic>>[];
        final timer = Timer(const Duration(seconds: 3), () {
          if (!closeCompleter.isCompleted) {
            closeCompleter.complete();
          }
        });

        channel.stream.listen(
          (data) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            messages.add(msg);
          },
          onDone: () {
            if (!closeCompleter.isCompleted) {
              closeCompleter.complete();
            }
          },
        );

        sendMessage(channel, const SessionStart(
          origin: 'https://evil.com',
          tutorialUrl: 'https://evil.com/test',
        ));

        await closeCompleter.future;
        timer.cancel();

        // Should have received session_denied
        expect(messages.any((m) => m['type'] == 'session_denied'), isTrue);

        // No session should be created
        expect(sessionManager.sessions.length, 0);
      });
    });

    group('exec with permission flow', () {
      test('first exec triggers permission dialog and VM launch on allow', () async {
        await startServer(autoDecision: PermissionDecision.allow);
        final channel = await connectToServer();

        // Start session
        sendMessage(channel, const SessionStart(
          origin: 'http://localhost:8080',
          tutorialUrl: 'http://localhost:8080/test',
        ));

        // Wait for session to be created
        await Future.delayed(const Duration(milliseconds: 200));

        // Get session ID from the session manager
        final session = sessionManager.sessions.first;
        final sessionId = session.sessionId;

        // Collect messages while we send exec
        final messagesFuture = collectMessages(
          channel,
          timeout: const Duration(seconds: 10),
        );

        sendMessage(channel, Exec(sessionId: sessionId, command: 'echo hello'));

        final messages = await messagesFuture;

        // Should receive session_ready after permission granted
        final sessionReady = messages.where((m) => m['type'] == 'session_ready').toList();
        expect(sessionReady.length, greaterThanOrEqualTo(1));
        expect(sessionReady.first['vm_name'], startsWith('lighthouse-'));

        // VM should have been launched
        expect(fakeMultipass.launchedVms.length, 1);

        await channel.sink.close();
      });

      test('first exec with deny results in session_denied and connection close', () async {
        await startServer(autoDecision: PermissionDecision.deny);
        final channel = await connectToServer();

        // Start session
        sendMessage(channel, const SessionStart(
          origin: 'http://localhost:8080',
          tutorialUrl: 'http://localhost:8080/test',
        ));

        await Future.delayed(const Duration(milliseconds: 200));

        // Get session ID
        final session = sessionManager.sessions.first;
        final sessionId = session.sessionId;

        // Collect messages
        final messagesFuture = collectMessages(
          channel,
          timeout: const Duration(seconds: 5),
        );

        sendMessage(channel, Exec(sessionId: sessionId, command: 'echo hello'));

        final messages = await messagesFuture;

        // Should have received session_denied
        expect(messages.any((m) => m['type'] == 'session_denied'), isTrue);

        // Session should be purged
        expect(sessionManager.sessions.length, 0);
      });
    });

    group('session_resume', () {
      test('resume unknown session returns error', () async {
        await startServer(autoDecision: PermissionDecision.allow);
        final channel = await connectToServer();

        final messagesFuture = collectMessages(
          channel,
          timeout: const Duration(seconds: 3),
        );

        sendMessage(channel, const SessionResume(sessionId: 'nonexistent-session'));

        final messages = await messagesFuture;

        // Should receive error
        expect(messages.any((m) => m['type'] == 'error'), isTrue);
        final error = messages.firstWhere((m) => m['type'] == 'error');
        expect(error['code'], equals('SESSION_UNKNOWN'));

        await channel.sink.close();
      });
    });

    group('command sanitizer', () {
      test('blocked command returns COMMAND_BLOCKED error', () async {
        await startServer(autoDecision: PermissionDecision.allow);
        final channel = await connectToServer();

        // Start session
        sendMessage(channel, const SessionStart(
          origin: 'http://localhost:8080',
          tutorialUrl: 'http://localhost:8080/test',
        ));

        await Future.delayed(const Duration(milliseconds: 200));

        final session = sessionManager.sessions.first;
        final sessionId = session.sessionId;

        // Use a broadcast stream to allow multiple listeners
        final broadcastStream = channel.stream.asBroadcastStream();

        // First exec to get session ready
        final initCloseCompleter = Completer<void>();
        final initTimer = Timer(const Duration(seconds: 10), () {
          if (!initCloseCompleter.isCompleted) {
            initCloseCompleter.complete();
          }
        });

        broadcastStream.listen(
          (data) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (['exec_done', 'error', 'agent_error', 'session_denied'].contains(msg['type'])) {
              if (!initCloseCompleter.isCompleted) {
                initCloseCompleter.complete();
              }
            }
          },
          onDone: () {
            if (!initCloseCompleter.isCompleted) {
              initCloseCompleter.complete();
            }
          },
        );

        sendMessage(channel, Exec(sessionId: sessionId, command: 'echo init'));

        await initCloseCompleter.future;
        initTimer.cancel();

        // Wait for session to be ready
        await Future.delayed(const Duration(milliseconds: 500));

        // Now test blocked command with the same broadcast stream
        final closeCompleter = Completer<void>();
        final messages = <Map<String, dynamic>>[];
        final timer = Timer(const Duration(seconds: 3), () {
          if (!closeCompleter.isCompleted) {
            closeCompleter.complete();
          }
        });

        broadcastStream.listen(
          (data) {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            messages.add(msg);
            if (['exec_done', 'error', 'agent_error', 'session_denied'].contains(msg['type'])) {
              if (!closeCompleter.isCompleted) {
                closeCompleter.complete();
              }
            }
          },
          onDone: () {
            if (!closeCompleter.isCompleted) {
              closeCompleter.complete();
            }
          },
        );

        sendMessage(channel, Exec(sessionId: sessionId, command: 'rm -rf /'));

        await closeCompleter.future;
        timer.cancel();

        // Should receive COMMAND_BLOCKED error
        expect(messages.any((m) => m['code'] == 'COMMAND_BLOCKED'), isTrue);

        await channel.sink.close();
      });
    });
  });
}
