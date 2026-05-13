import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/message.dart';

class WebSocketServer {
  WebSocketServer({this.port = 50051});

  final int port;
  final MessageCodec _codec = const MessageCodec();
  final Set<WebSocketChannel> _connections = <WebSocketChannel>{};
  HttpServer? _server;

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    final handler = webSocketHandler(
      (channel, subprotocol) => _handleConnection(channel),
    );

    if (kDebugMode) {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        port,
      );
      stdout.writeln('Lighthouse Agent listening on ws://localhost:$port');
      return;
    }

    if (!await hasValidCertificates()) {
      stderr.writeln(
        'TLS certificates are missing. Expected ${await getCertPath()} and ${await getKeyPath()}.',
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
    stdout.writeln('Lighthouse Agent listening on wss://localhost:$port');
  }

  Future<void> stop() async {
    for (final connection in _connections.toList()) {
      await connection.sink.close();
    }
    _connections.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<bool> hasValidCertificates() async {
    final cert = File(await getCertPath());
    final key = File(await getKeyPath());
    return cert.existsSync() && key.existsSync();
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
    final supportPath = await PathProviderLinux().getApplicationSupportPath();
    if (supportPath == null) {
      throw StateError('Could not resolve application support directory.');
    }

    final dir = Directory(p.join(supportPath, 'lighthouse'));
    await dir.create(recursive: true);
    return dir;
  }

  void _handleConnection(WebSocketChannel channel) {
    _connections.add(channel);
    stdout.writeln('WebSocket client connected');

    channel.stream.listen(
      (message) {
        if (message is! String) {
          channel.sink.add(
            _codec.encode(
              const AgentError(
                code: 'INVALID_MESSAGE',
                message: 'Only JSON text messages are supported',
              ),
            ),
          );
          return;
        }

        try {
          final parsed = _codec.decode(message);
          stdout.writeln('Received ${parsed.type}');
          channel.sink.add(
            _codec.encode(
              const AgentError(
                code: 'NOT_IMPLEMENTED',
                message: 'Day 1 WebSocket skeleton received the message',
              ),
            ),
          );
        } on Object catch (error) {
          channel.sink.add(
            _codec.encode(
              AgentError(code: 'INVALID_JSON', message: error.toString()),
            ),
          );
        }
      },
      onDone: () {
        _connections.remove(channel);
        stdout.writeln('WebSocket client disconnected');
      },
      onError: (Object error, StackTrace stackTrace) {
        _connections.remove(channel);
        stderr.writeln('WebSocket error: $error');
        stderr.writeln(stackTrace);
      },
    );
  }
}
