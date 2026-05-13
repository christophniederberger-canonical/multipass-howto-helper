import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

enum TrayState { normal, error }

class LighthouseTray {
  LighthouseTray();

  String _tooltip = 'Lighthouse Agent';

  Future<void> setupTrayIcon() async {
    if (kDebugMode) stdout.writeln('Tray setup placeholder initialized.');
  }

  Future<void> setTrayState(TrayState state) async {
    if (kDebugMode) stdout.writeln('Tray state changed to: $state');
    _tooltip = state == TrayState.error
        ? 'Multipass not found'
        : 'Lighthouse Agent';
    if (kDebugMode) stdout.writeln('Tray tooltip: $_tooltip');
  }

  Future<void> dispose() async {
    // No-op for Day 1 fallback.
  }

  Future<void> showStatus() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Gracefully shuts down the agent: stops the server, disposes tray,
  /// then exits the process.
  Future<void> quit() async {
    await dispose();
    exit(0);
  }
}
