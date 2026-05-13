import 'dart:io';

import 'package:path/path.dart' as p;

class AutostartRegistration {
  const AutostartRegistration({required this.appDataDir});

  final Directory appDataDir;

  Future<void> registerIfNeeded() async {
    final lighthouseDir = Directory(p.join(appDataDir.path, 'lighthouse'));
    await lighthouseDir.create(recursive: true);

    final marker = File(p.join(lighthouseDir.path, '.autostart_registered'));
    if (await marker.exists()) {
      return;
    }

    try {
      await _registerLinuxAutostart();
      await marker.writeAsString(DateTime.now().toIso8601String());
    } on Object catch (error, stackTrace) {
      stderr.writeln('Autostart registration failed: $error');
      stderr.writeln(stackTrace);
    }
  }

  Future<void> _registerLinuxAutostart() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set');
    }

    final autostartDir = Directory(p.join(home, '.config', 'autostart'));
    await autostartDir.create(recursive: true);

    final executable = Platform.resolvedExecutable;
    final desktopFile = File(p.join(autostartDir.path, 'lighthouse.desktop'));
    await desktopFile.writeAsString('''
[Desktop Entry]
Name=Lighthouse Agent
Comment=Local bridge agent for Canonical tutorials
Exec=$executable
Icon=lighthouse
Type=Application
Categories=System;Utility;
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
''');
  }
}
