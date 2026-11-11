import 'package:test/test.dart';
import 'package:voxlog/voxlog.dart';

void main() {
  group('voxlog - Core Logging Suite', () {
    test('LogLevel comparisons', () {
      expect(LogLevel.trace < LogLevel.debug, isTrue);
      expect(LogLevel.debug < LogLevel.info, isTrue);
      expect(LogLevel.info < LogLevel.warn, isTrue);
      expect(LogLevel.warn < LogLevel.error, isTrue);
      expect(LogLevel.error < LogLevel.critical, isTrue);
    });

    test('PatternFormatter template replacements', () {
      const fmt = PatternFormatter('[%n] [%l] %v');
      final record = LogRecord(
        time: DateTime(2026, 11, 11, 12, 0, 0),
        level: LogLevel.info,
        loggerName: 'CLI',
        message: 'Ready',
      );
      expect(fmt.format(record), '[CLI] [INFO] Ready');
    });

    test('Logger level filtering', () {
      final messages = <String>[];
      final logger = Logger(
        name: 'TEST',
        level: LogLevel.warn,
        sinks: [CallbackSink((r) => messages.add(r.message))],
      );

      logger.debug('Debug skipped');
      logger.info('Info skipped');
      logger.warn('Warn recorded');
      logger.error('Error recorded');

      expect(messages, ['Warn recorded', 'Error recorded']);
    });

    test('RingBufferSink circular bounds', () {
      final ring = RingBufferSink(capacity: 2);
      final logger = Logger(name: 'RING', sinks: [ring]);

      logger.info('A');
      logger.info('B');
      expect(ring.length, 2);
      expect(ring.records.map((r) => r.message).toList(), ['A', 'B']);

      logger.info('C');
      expect(ring.length, 2);
      expect(ring.records.map((r) => r.message).toList(), ['B', 'C']);
    });
  });
}
