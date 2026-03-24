import 'dart:convert';
import 'dart:developer' as dev;

class AppLogger {
  static void info(String event, {Map<String, Object?> data = const {}}) {
    _log('INFO', event, data);
  }

  static void error(String event, {Map<String, Object?> data = const {}}) {
    _log('ERROR', event, data);
  }

  static void _log(String level, String event, Map<String, Object?> data) {
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'data': data,
    };
    dev.log(jsonEncode(payload));
  }
}
