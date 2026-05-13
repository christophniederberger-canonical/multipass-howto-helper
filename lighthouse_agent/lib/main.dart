import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:window_manager/window_manager.dart';

import 'agent/websocket_server.dart';
import 'platform/autostart_linux.dart';
import 'ui/status_window.dart';
import 'ui/tray_icon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(900, 600),
    center: true,
    title: 'Lighthouse Agent',
    skipTaskbar: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  final tray = LighthouseTray();
  await tray.setupTrayIcon();

  final supportPath = await PathProviderLinux().getApplicationSupportPath();
  if (supportPath == null) {
    stderr.writeln('Could not resolve application support directory.');
    await tray.setTrayState(TrayState.error);
    return;
  }

  final appDataDir = Directory(supportPath);
  if (Platform.isLinux) {
    await AutostartRegistration(appDataDir: appDataDir).registerIfNeeded();
  }

  final server = WebSocketServer();
  if (!kDebugMode && !await server.hasValidCertificates()) {
    stderr.writeln('TLS certificates are missing. TODO: show mkcert setup UI.');
  }

  try {
    await server.start();
  } on Object catch (error, stackTrace) {
    stderr.writeln('Failed to start WebSocket server: $error');
    stderr.writeln(stackTrace);
    await tray.setTrayState(TrayState.error);
  }

  runApp(const LighthouseApp());
}

class LighthouseApp extends StatelessWidget {
  const LighthouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lighthouse Agent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const StatusWindow(),
    );
  }
}
