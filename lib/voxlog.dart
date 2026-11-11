/// Fast, multi-sink structured logging for Dart, CLI applications, and game engines.
library voxlog;

import 'dart:collection';
import 'dart:io' as io;

/// Severity level of a log message.
enum LogLevel implements Comparable<LogLevel> {
  trace(0, 'TRACE', 'T'),
  debug(1, 'DEBUG', 'D'),
  info(2, 'INFO', 'I'),
  warn(3, 'WARN', 'W'),
  error(4, 'ERROR', 'E'),
  critical(5, 'CRITICAL', 'C'),
  off(6, 'OFF', 'O');

  final int value;
  final String label;
  final String shortLabel;

  const LogLevel(this.value, this.label, this.shortLabel);

  @override
  int compareTo(LogLevel other) => value.compareTo(other.value);

  bool operator >=(LogLevel other) => value >= other.value;
  bool operator <=(LogLevel other) => value <= other.value;
  bool operator >(LogLevel other) => value > other.value;
  bool operator <(LogLevel other) => value < other.value;
}

/// A structured diagnostic entry.
final class LogRecord {
  final DateTime time;
  final LogLevel level;
  final String loggerName;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const LogRecord({
    required this.time,
    required this.level,
    required this.loggerName,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() => '[$time] [$loggerName] [${level.label}] $message';
}

/// Formats a [LogRecord] into a string based on a pattern template.
final class PatternFormatter {
  final String pattern;

  const PatternFormatter([this.pattern = r'[%T.%e] [%n] [%^%l%$] %v']);

  static const String _ansiReset = '\x1B[0m';
  static const String _ansiCyan = '\x1B[36m';
  static const String _ansiBlue = '\x1B[34m';
  static const String _ansiGreen = '\x1B[32m';
  static const String _ansiYellow = '\x1B[33m';
  static const String _ansiRed = '\x1B[31m';
  static const String _ansiBoldRed = '\x1B[1;31m';

  String _levelColor(LogLevel level) => switch (level) {
        LogLevel.trace => _ansiCyan,
        LogLevel.debug => _ansiBlue,
        LogLevel.info => _ansiGreen,
        LogLevel.warn => _ansiYellow,
        LogLevel.error => _ansiRed,
        LogLevel.critical => _ansiBoldRed,
        LogLevel.off => '',
      };

  String format(LogRecord record, {bool useColor = false}) {
    final t = record.time;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    final date =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

    final colorStart = useColor ? _levelColor(record.level) : '';
    final colorEnd = useColor ? _ansiReset : '';

    var result = pattern
        .replaceAll('%v', record.message)
        .replaceAll('%n', record.loggerName)
        .replaceAll('%l', record.level.label)
        .replaceAll('%L', record.level.shortLabel)
        .replaceAll('%T', '$h:$m:$s')
        .replaceAll('%e', ms)
        .replaceAll('%Y-%m-%d', date)
        .replaceAll('%^', colorStart)
        .replaceAll(r'%$', colorEnd);

    if (record.error != null) {
      result += '\nError: ${record.error}';
    }
    if (record.stackTrace != null) {
      result += '\n${record.stackTrace}';
    }
    return result;
  }
}

/// Abstract destination target for log records.
abstract class LogSink {
  LogLevel level;
  PatternFormatter formatter;

  LogSink({
    this.level = LogLevel.trace,
    this.formatter = const PatternFormatter(),
  });

  void log(LogRecord record);
  void flush() {}
  void close() {}
}

/// Console sink that writes to stdout (and stderr for errors) with ANSI color support.
final class ConsoleSink extends LogSink {
  final bool enableColor;
  final bool splitErrorsToStderr;

  ConsoleSink({
    super.level,
    super.formatter,
    bool? enableColor,
    this.splitErrorsToStderr = false,
  }) : enableColor = enableColor ?? io.stdout.hasTerminal;

  @override
  void log(LogRecord record) {
    if (record.level < level) return;
    final line = formatter.format(record, useColor: enableColor);
    if (splitErrorsToStderr && record.level >= LogLevel.error) {
      io.stderr.writeln(line);
    } else {
      io.stdout.writeln(line);
    }
  }
}

/// File sink that appends formatted log records to a specified file.
final class FileSink extends LogSink {
  final io.File file;
  io.IOSink? _sink;

  FileSink(
    String filePath, {
    super.level,
    super.formatter,
    bool append = true,
  }) : file = io.File(filePath) {
    file.parent.createSync(recursive: true);
    _sink = file.openWrite(mode: append ? io.FileMode.append : io.FileMode.write);
  }

  @override
  void log(LogRecord record) {
    if (record.level < level) return;
    final line = formatter.format(record, useColor: false);
    _sink?.writeln(line);
    if (record.level >= LogLevel.error) {
      flush();
    }
  }

  @override
  void flush() {
    _sink?.flush();
  }

  @override
  void close() {
    _sink?.close();
    _sink = null;
  }
}

/// In-memory circular buffer sink retaining the most recent [capacity] log records.
final class RingBufferSink extends LogSink {
  final int capacity;
  final Queue<LogRecord> _buffer;

  RingBufferSink({this.capacity = 256, super.level, super.formatter})
      : _buffer = Queue<LogRecord>() {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity', 'must be > 0');
  }

  Iterable<LogRecord> get records => _buffer;
  int get length => _buffer.length;
  void clear() => _buffer.clear();

  @override
  void log(LogRecord record) {
    if (record.level < level) return;
    if (_buffer.length >= capacity) {
      _buffer.removeFirst();
    }
    _buffer.addLast(record);
  }
}

/// Callback sink that dispatches [LogRecord]s to a listener function.
final class CallbackSink extends LogSink {
  final void Function(LogRecord record) onRecord;

  CallbackSink(this.onRecord, {super.level, super.formatter});

  @override
  void log(LogRecord record) {
    if (record.level < level) return;
    onRecord(record);
  }
}

/// A named logger with a collection of output [sinks].
final class Logger {
  final String name;
  LogLevel level;
  final List<LogSink> sinks;

  Logger({
    required this.name,
    this.level = LogLevel.info,
    List<LogSink>? sinks,
  }) : sinks = sinks ?? [ConsoleSink()];

  bool shouldLog(LogLevel msgLevel) => level != LogLevel.off && msgLevel >= level;

  void log(
    LogLevel msgLevel,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!shouldLog(msgLevel)) return;
    final record = LogRecord(
      time: DateTime.now(),
      level: msgLevel,
      loggerName: name,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    for (final sink in sinks) {
      sink.log(record);
    }
  }

  void trace(String message) => log(LogLevel.trace, message);
  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warn(String message, [Object? error]) => log(LogLevel.warn, message, error);
  void error(String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.error, message, error, stack);
  void critical(String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.critical, message, error, stack);

  void setPattern(String pattern) {
    final fmt = PatternFormatter(pattern);
    for (final sink in sinks) {
      sink.formatter = fmt;
    }
  }

  void flush() {
    for (final sink in sinks) {
      sink.flush();
    }
  }
}

/// Global logger registry and convenience interface.
class _VoxlogRegistry {
  final Map<String, Logger> _loggers = {};
  Logger _defaultLogger = Logger(name: 'app', level: LogLevel.info);

  Logger get defaultLogger => _defaultLogger;
  set defaultLogger(Logger logger) => _defaultLogger = logger;

  Logger get(String name) => _loggers.putIfAbsent(name, () => Logger(name: name));

  Logger stdoutColor(String name, {LogLevel level = LogLevel.info}) {
    final logger = Logger(
      name: name,
      level: level,
      sinks: [ConsoleSink(enableColor: true)],
    );
    _loggers[name] = logger;
    return logger;
  }

  Logger file(String name, String filePath, {LogLevel level = LogLevel.info}) {
    final logger = Logger(
      name: name,
      level: level,
      sinks: [FileSink(filePath)],
    );
    _loggers[name] = logger;
    return logger;
  }

  void setLevel(LogLevel level) {
    _defaultLogger.level = level;
    for (final l in _loggers.values) {
      l.level = level;
    }
  }

  void setPattern(String pattern) {
    _defaultLogger.setPattern(pattern);
    for (final l in _loggers.values) {
      l.setPattern(pattern);
    }
  }

  void trace(String msg) => _defaultLogger.trace(msg);
  void debug(String msg) => _defaultLogger.debug(msg);
  void info(String msg) => _defaultLogger.info(msg);
  void warn(String msg, [Object? error]) => _defaultLogger.warn(msg, error);
  void error(String msg, [Object? error, StackTrace? stack]) =>
      _defaultLogger.error(msg, error, stack);
  void critical(String msg, [Object? error, StackTrace? stack]) =>
      _defaultLogger.critical(msg, error, stack);
}

final _VoxlogRegistry voxlog = _VoxlogRegistry();
