import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class AppLogger {
  static File? _logFile;

  static Future<void> init() async {
    if (kIsWeb) {
      debugPrint('Logger initialized (Web mode - File logging disabled)');
      return;
    }
    
    try {
      final directory = await getApplicationSupportDirectory();
      _logFile = File('${directory.path}/lime_debug.log');
      
      // Rotate log if it gets too large (> 5MB)
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > 5 * 1024 * 1024) {
          await _logFile!.delete();
        }
      }
      
      await log('--- App Session Started: ${DateTime.now()} ---');
    } catch (e) {
      debugPrint('Failed to initialize logger: $e');
    }
  }

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] $message\n';
    
    // Always print to console
    debugPrint(message);
    
    // Write to file if initialized
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(logLine, mode: FileMode.append, flush: true);
      } catch (e) {
        debugPrint('Failed to write to log file: $e');
      }
    }
  }

  static Future<void> logError(dynamic error, [StackTrace? stack]) async {
    await log('ERROR: $error');
    if (stack != null) {
      await log('STACK TRACE:\n$stack');
    }
  }

  static Future<String> getLogPath() async {
    if (kIsWeb) return 'Web Console';
    if (_logFile != null) return _logFile!.path;
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}/lime_debug.log';
  }
}
