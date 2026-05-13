import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

class Logger {
  static Logger? _instance;
  static Logger get instance => _instance ??= Logger._();

  Logger._();

  File? _logFile;
  String? _logPath;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final cacheDir = await getApplicationCacheDirectory();
      final logDir = Directory(p.join(cacheDir.path, 'lighthouse_agent', 'logs'));
      
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      // Rotate logs - keep only 7 days of history
      await _rotateLogs(logDir);

      final timestamp = DateTime.now().toIso8601String().split('T')[0];
      _logPath = p.join(logDir.path, 'lighthouse_$timestamp.log');
      _logFile = File(_logPath!);
      _initialized = true;

      info('Logger initialized. Log file: $_logPath');
    } catch (e) {
      stderr.writeln('Failed to initialize logger: $e');
    }
  }

  Future<void> _rotateLogs(Directory logDir) async {
    try {
      final now = DateTime.now();
      final files = await logDir.list().toList();
      
      for (final file in files) {
        if (file is File && file.path.contains('lighthouse_')) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);
          if (age.inDays > 7) {
            await file.delete();
            debug('Rotated out old log: ${file.path}');
          }
        }
      }
    } catch (e) {
      stderr.writeln('Log rotation failed: $e');
    }
  }

  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase().padRight(7);
    final formattedMessage = '[$timestamp] [$levelStr] $message';

    // Always print to stdout/stderr based on level
    if (level == LogLevel.error) {
      stderr.writeln(formattedMessage);
      if (error != null) {
        stderr.writeln('  Error: $error');
      }
      if (stackTrace != null) {
        stderr.writeln('  StackTrace: $stackTrace');
      }
    } else {
      stdout.writeln(formattedMessage);
    }

    // Also write to log file
    if (_logFile != null) {
      final entry = StringBuffer(formattedMessage);
      if (error != null) {
        entry.writeln('  Error: $error');
      }
      if (stackTrace != null) {
        entry.writeln('  StackTrace: $stackTrace');
      }
      entry.writeln();
      
      _logFile!.writeAsStringSync(entry.toString(), mode: FileMode.append);
    }
  }

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warning(String message) => _log(LogLevel.warning, message);
  void error(String message, [Object? error, StackTrace? stackTrace]) => 
      _log(LogLevel.error, message, error, stackTrace);

  String? get logPath => _logPath;
}