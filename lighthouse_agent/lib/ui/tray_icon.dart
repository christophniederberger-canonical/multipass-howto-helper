import 'dart:io';

import 'package:window_manager/window_manager.dart';

enum TrayState { normal, error }

class LighthouseTray {
  LighthouseTray();

  Future<void> setupTrayIcon() async {
    // Day 1 fallback: no native tray in this environment.
    stdout.writeln('Tray setup placeholder initialized.');
  }

  Future<void> setTrayState(TrayState state) async {
    stdout.writeln('Tray state changed to: $state');
  }

  Future<void> dispose() async {
    // No-op for Day 1 fallback.
  }

  Future<void> showStatus() async {
    windowManager.show();
    windowManager.focus();
  }

  Future<void> quit() async {
    await dispose();
    exit(0);
  }
}
