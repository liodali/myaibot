/// Minimal leveled logger (debug/info/warn/error) with level filtering
/// controlled by the LOG_LEVEL environment variable.
library;

import 'dart:io';

enum Level { debug, info, warn, error }

const _order = {
  Level.debug: 10,
  Level.info: 20,
  Level.warn: 30,
  Level.error: 40,
};

int _thresholdFor(String level) {
  for (final l in Level.values) {
    if (l.name == level.toLowerCase()) return _order[l]!;
  }
  return _order[Level.info]!;
}

class Logger {
  final int threshold;
  final bool debugEnabled;

  Logger(String level)
    : threshold = _thresholdFor(level),
      debugEnabled = _thresholdFor(level) <= _order[Level.debug]!;

  void debug(Object? message) => _emit(Level.debug, message);
  void info(Object? message) => _emit(Level.info, message);
  void warn(Object? message) => _emit(Level.warn, message);
  void error(Object? message, [Object? error, StackTrace? stack]) {
    var text = message?.toString() ?? '';
    if (error != null) text += ' $error';
    if (stack != null && debugEnabled) text += '\n$stack';
    _emit(Level.error, text);
  }

  void _emit(Level level, Object? message) {
    if (_order[level]! < threshold) return;
    final ts = DateTime.now().toUtc().toIso8601String();
    final line = '[$ts] ${level.name.toUpperCase()} $message';
    if (level == Level.error) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }
}

final logger = Logger(Platform.environment['LOG_LEVEL'] ?? 'info');
