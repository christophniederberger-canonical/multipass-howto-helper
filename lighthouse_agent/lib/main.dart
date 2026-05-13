import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'agent/multipass_wrapper.dart';
import 'agent/websocket_server.dart';
import 'platform/autostart_linux.dart';
import 'ui/permission_dialog.dart';
import 'ui/status_window.dart';
import 'ui/tray_icon.dart';

// Global key to access navigator context for permission dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

late final LighthouseTray _tray;
late final WebSocketServer _server;

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

  _tray = LighthouseTray();
  await _tray.setupTrayIcon();

  final supportDir = await getApplicationSupportDirectory();
  final appDataDir = Directory(supportDir.path);
  if (Platform.isLinux) {
    await AutostartRegistration(appDataDir: appDataDir).registerIfNeeded();
  }

  // Create instances
  const multipass = MultipassWrapper();
  const permissionDialog = PermissionDialog();

  _server = WebSocketServer(
    multipass: multipass,
    onPermissionRequested: (origin) => permissionDialog.requestTutorialPermission(
      context: navigatorKey.currentContext!,
      origin: origin,
    ),
  );
  if (!kDebugMode && !await _server.hasValidCertificates()) {
    stderr.writeln('TLS certificates are missing. TODO: show mkcert setup UI.');
  }

  // Check Multipass availability before starting the server.
  final multipassAvailable = await multipass.isAvailable();
  if (!multipassAvailable) {
    stderr.writeln('Multipass not found in PATH. Please install Multipass.');
    await _tray.setTrayState(TrayState.error);
  } else {
    stdout.writeln('Multipass detected.');
  }

  try {
    await _server.start();
  } on Object catch (error, stackTrace) {
    stderr.writeln('Failed to start WebSocket server: $error');
    if (kDebugMode) stderr.writeln(stackTrace);
    await _tray.setTrayState(TrayState.error);
  }

  runApp(const LighthouseApp());
}

class LighthouseApp extends StatelessWidget {
  const LighthouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
