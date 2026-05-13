import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'multipass_wrapper.dart';
import '../models/message.dart';
import '../models/session.dart';
import 'command_sanitizer.dart';
import 'origin_validator.dart';
import 'session_manager.dart';

class WebSocketServer {
  WebSocketServer({
    this.port = 50051,
    SessionManager? sessionManager,
    OriginValidator? originValidator,
    CommandSanitizer? commandSanitizer,
  })  : _sessions = sessionManager ?? SessionManager(),
        _originValidator = originValidator ?? const OriginValidator(),
        _sanitizer = commandSanitizer ?? const CommandSanitizer();

  final int port;
  final MessageCodec _codec = const MessageCodec();
  final Set<WebSocketChannel> _connections = <WebSocketChannel>{};
  final Map<WebSocketChannel, String?> _channelToSession =
      <WebSocketChannel, String?>{};
  final SessionManager _sessions;
  final OriginValidator _originValidator;
  final CommandSanitizer _sanitizer;
  HttpServer? _server;

  Future<void> start() async {
    if (_server != null) return;

    final handler = webSocketHandler(
      (channel, subprotocol) => _handleConnection(channel),
    );

    if (kDebugMode) {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        port,
      );
      _log('Lighthouse Agent listening on ws://localhost:$port');
      return;
    }

    if (!await hasValidCertificates()) {
      throw StateError(
        'TLS certificates are missing. '
        'Expected: ${await getCertPath()} and ${await getKeyPath()}.',
      );
    }

    final context = SecurityContext()
      ..useCertificateChain(await getCertPath())
      ..usePrivateKey(await getKeyPath());

    final secureServer = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      port,
      context,
    );
    _server = secureServer;
    shelf_io.serveRequests(secureServer, handler);
    _log('Lighthouse Agent listening on wss://localhost:$port');
  }

  Future<void> stop() async {
    for (final connection in _connections.toList()) {
      await connection.sink.close();
    }
    _connections.clear();
    _channelToSession.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<bool> hasValidCertificates() async {
    final cert = File(await getCertPath());
    final key = File(await getKeyPath());
    return await cert.exists() && await key.exists();
  }

  Future<String> getCertPath() async {
    final dir = await _lighthouseDataDir();
    return p.join(dir.path, 'localhost.pem');
  }

  Future<String> getKeyPath() async {
    final dir = await _lighthouseDataDir();
    return p.join(dir.path, 'localhost-key.pem');
  }

  Future<Directory> _lighthouseDataDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'lighthouse'));
    await dir.create(recursive: true);
    return dir;
  }

  // ----------------------------------------------------------------
  // Connection handling
  // ----------------------------------------------------------------

  void _handleConnection(WebSocketChannel channel) {
    _connections.add(channel);
    _channelToSession[channel] = null;
    _log('WebSocket client connected');

    channel.stream.listen(
      (message) => _onMessage(channel, message),
      onDone: () => _onConnectionClosed(channel),
      onError: (Object error, StackTrace stackTrace) {
        _onConnectionClosed(channel);
        _err('WebSocket error: $error');
        if (kDebugMode) _err(stackTrace.toString());
      },
    );
  }

  void _onMessage(WebSocketChannel channel, Object? message) {
    if (message is! String) {
      _send(channel, const AgentError(
        code: 'INVALID_MESSAGE',
        message: 'Only JSON text messages are supported',
      ));
      return;
    }

    if (message.length > 65536) {
      _send(channel, const AgentError(
        code: 'MESSAGE_TOO_LARGE',
        message: 'Max message size is 64 KiB',
      ));
      return;
    }

    LighthouseMessage parsed;
    try {
      parsed = _codec.decode(message);
    } on FormatException catch (e) {
      _send(channel, AgentError(
        code: 'INVALID_JSON',
        message: 'Malformed JSON: ${e.message}',
      ));
      return;
    } on Object catch (_) {
      _send(channel, const AgentError(
        code: 'INVALID_JSON',
        message: 'Malformed JSON',
      ));
      return;
    }

    _log('Received ${parsed.type}');

    switch (parsed) {
      case SessionStart(:final origin, :final tutorialUrl):
        _handleSessionStart(channel, origin: origin, tutorialUrl: tutorialUrl);
      case SessionResume(:final sessionId):
        _handleSessionResume(channel, sessionId: sessionId);
      case Exec(:final sessionId, :final command):
        // TODO(day3): remove test hook — temporary Day 2 integration test.
        if (command == '__test_multipass__') {
          _handleTestMultipass(
            Exec(sessionId: sessionId, command: command),
            channel,
          );
          return;
        }
        _handleExec(channel, sessionId: sessionId, command: command);
      case Finish(:final sessionId):
        _handleFinish(channel, sessionId: sessionId);
      default:
        _send(channel, const AgentError(
          code: 'INVALID_DIRECTION',
          message: 'Message type is not valid from client',
        ));
    }
  }

  void _handleSessionStart(
    WebSocketChannel channel, {
    required String origin,
    required String tutorialUrl,
  }) {
    if (!_originValidator.isAllowed(origin)) {
      _send(channel, const SessionDenied());
      channel.sink.close();
      _log('Origin rejected: $origin');
      return;
    }

    final tutorialUri = Uri.tryParse(tutorialUrl);
    if (tutorialUri == null || !_originValidator.isAllowed(tutorialUrl)) {
      _send(channel, const AgentError(
        code: 'INVALID_TUTORIAL_URL',
        message: 'tutorial_url does not match an allowed origin',
      ));
      return;
    }

    final sessionId = const Uuid().v4();
    final vmName = 'lighthouse-${sessionId.substring(0, 8)}';

    final session = Session(
      sessionId: sessionId,
      tutorialUrl: tutorialUrl,
      origin: origin,
      state: SessionState.pending,
      vmName: vmName,
    );

    _sessions.add(session);
    _channelToSession[channel] = sessionId;

    _send(channel, SessionReady(sessionId: sessionId, vmName: vmName));
    _log('Session started: $sessionId, VM: $vmName');
  }

  void _handleSessionResume(
    WebSocketChannel channel, {
    required String sessionId,
  }) {
    final session = _sessions.find(sessionId);
    if (session == null || session.state == SessionState.purged) {
      _send(channel, LighthouseError(
        sessionId: sessionId,
        code: 'SESSION_UNKNOWN',
        message: 'Session not found or has expired',
      ));
      return;
    }

    if (session.expiresAt != null &&
        DateTime.now().isAfter(session.expiresAt!)) {
      _send(channel, LighthouseError(
        sessionId: sessionId,
        code: 'SESSION_EXPIRED',
        message: 'Session has expired',
      ));
      _sessions.remove(sessionId);
      return;
    }

    _channelToSession[channel] = sessionId;
    session.state = SessionState.ready;
    session.expiresAt = null;

    _send(channel, SessionReady(
      sessionId: sessionId,
      vmName: session.vmName ?? 'unknown',
    ));
    _log('Session resumed: $sessionId');
  }

  void _handleExec(
    WebSocketChannel channel, {
    required String sessionId,
    required String command,
  }) {
    final session = _sessions.find(sessionId);
    if (session == null) {
      _send(channel, LighthouseError(
        sessionId: sessionId,
        code: 'SESSION_UNKNOWN',
        message: 'No active session for this exec',
      ));
      return;
    }

    final result = _sanitizer.check(command);
    if (!result.isSafe) {
      _send(channel, LighthouseError(
        sessionId: sessionId,
        code: 'COMMAND_BLOCKED',
        message: result.reason ?? 'Command blocked by sanitizer',
      ));
      return;
    }

    _send(channel, const AgentError(
      code: 'NOT_IMPLEMENTED',
      message: 'Command execution will be available in Day 2',
    ));
  }

  void _handleFinish(WebSocketChannel channel, {required String sessionId}) {
    final session = _sessions.find(sessionId);
    if (session == null) {
      _send(channel, LighthouseError(
        sessionId: sessionId,
        code: 'SESSION_UNKNOWN',
        message: 'No active session to finish',
      ));
      return;
    }

    session.state = SessionState.purged;
    _sessions.remove(sessionId);
    _channelToSession[channel] = null;

    _send(channel, const AgentError(
      code: 'NOT_IMPLEMENTED',
      message: 'VM cleanup will be available in Day 2',
    ));
    _log('Session finished: $sessionId');
  }

  void _onConnectionClosed(WebSocketChannel channel) {
    _connections.remove(channel);
    final sessionId = _channelToSession.remove(channel);
    _log('WebSocket client disconnected (session: $sessionId)');

    if (sessionId != null) {
      final session = _sessions.find(sessionId);
      if (session != null && session.state != SessionState.purged) {
        session.state = SessionState.expiring;
        session.expiresAt = DateTime.now().add(const Duration(minutes: 30));
        _log('Session $sessionId entering 30-min expiry window');
      }
    }
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  void _send(WebSocketChannel channel, LighthouseMessage message) {
    channel.sink.add(_codec.encode(message));
  }

  void _log(String message) {
    if (kDebugMode) stdout.writeln(message);
  }

  void _err(String message) {
    stderr.writeln(message);
  }

  // TODO(day3): remove test hook — temporary Day 2 integration test.
  Future<void> _handleTestMultipass(Exec exec, WebSocketChannel channel) async {
    const wrapper = MultipassWrapper();
    final vmName = 'lighthouse-test-${DateTime.now().millisecondsSinceEpoch}';

    try {
      await wrapper.launch(vmName: vmName);
      await for (final event in wrapper.exec(
        vmName: vmName,
        command: 'echo hello from multipass',
      )) {
        if (event is CommandOutput) {
          channel.sink.add(
            _codec.encode(
              Output(
                sessionId: exec.sessionId,
                stream: event.stream == 'stderr'
                    ? OutputStream.stderr
                    : OutputStream.stdout,
                data: event.data,
              ),
            ),
          );
        } else if (event is ExecResult) {
          channel.sink.add(
            _codec.encode(
              ExecDone(
                sessionId: exec.sessionId,
                exitCode: event.exitCode,
              ),
            ),
          );
        }
      }
    } on Object catch (error, stackTrace) {
      stderr.writeln('Test multipass hook failed: $error');
      stderr.writeln(stackTrace);
      channel.sink.add(
        _codec.encode(
          LighthouseError(
            sessionId: exec.sessionId,
            code: 'MULTIPASS_ERROR',
            message: error.toString(),
          ),
        ),
      );
    } finally {
      // Always clean up the test VM, even on error.
      try {
        await wrapper.delete(vmName: vmName);
      } on Object catch (error) {
        stderr.writeln('Failed to clean up test VM $vmName: $error');
      }
    }
  }
}
