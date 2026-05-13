import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum TrayState { normal, error }

class LighthouseTray {
  LighthouseTray();

  final SystemTray _systemTray = SystemTray();

  Future<String> _getIconPath(TrayState state) async {
    // In dev mode, assets are in the package root.
    // In release/build, they are in the build directory.
    // Try common locations to find the icon.
    final appDir = await getApplicationSupportDirectory();
    final possiblePaths = [
      path.join(appDir.path, 'data', 'flutter_assets', 'assets', state == TrayState.error ? 'icon_error.png' : 'icon_normal.png'),
      path.join(appDir.path, '..', '..', '..', 'flutter_assets', 'assets', state == TrayState.error ? 'icon_error.png' : 'icon_normal.png'),
      path.join('/home', 'christoph.niederberger@canonical.com', '.local', 'share', 'lighthouse_agent', 'flutter_assets', 'assets', state == TrayState.error ? 'icon_error.png' : 'icon_normal.png'),
    ];

    // For now, use a fallback path — in production, the icon would be bundled
    // and we would resolve it properly at runtime.
    // The system_tray package on Linux expects a valid file path.
    if (kDebugMode) {
      return possiblePaths[0];
    }
    for (final p in possiblePaths) {
      if (await File(p).exists()) return p;
    }
    return possiblePaths[0];
  }

  Future<void> setupTrayIcon() async {
    final iconPath = await _getIconPath(TrayState.normal);

    await _systemTray.initSystemTray(
      title: 'Lighthouse Agent',
      iconPath: iconPath,
      toolTip: 'Lighthouse Agent',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Show Status',
        onClicked: (menuItem) => showStatus(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) => quit(),
      ),
    ]);

    await _systemTray.setContextMenu(menu);

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        showStatus();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });

    if (kDebugMode) stdout.writeln('Tray setup complete. Icon: $iconPath');
  }

  Future<void> setTrayState(TrayState state) async {
    final iconPath = await _getIconPath(state);
    final tooltip = state == TrayState.error
        ? 'Multipass not found — Lighthouse Agent'
        : 'Lighthouse Agent';

    await _systemTray.setImage(iconPath);
    await _systemTray.setToolTip(tooltip);

    if (kDebugMode) stdout.writeln('Tray state changed to: $state');
  }

  Future<void> dispose() async {
    await _systemTray.destroy();
  }

  Future<void> showStatus() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Gracefully shuts down the agent: stops the server, disposes tray,
  /// then exits the process.
  Future<void> quit() async {
    await windowManager.hide();
    await dispose();
    exit(0);
  }
}
