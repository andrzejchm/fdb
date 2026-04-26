import 'package:fdb/log_marker_detector.dart';
import 'package:test/test.dart';

void main() {
  group('didLogGainMarker', () {
    test('detects marker in appended content', () {
      const before = 'line 1\nline 2\n';
      const after = 'line 1\nline 2\nReloaded 0 libraries in 44ms.\n';

      final result = didLogGainMarker(
        before: before,
        after: after,
        marker: 'Reloaded',
      );

      expect(result, isTrue);
    });

    test('detects marker when the log tail is rewritten before prior eof', () {
      const before = 'header\n'
          'older log line\n'
          'tail AAAAA heartbeat counter=0\n'
          'tail BBBBB heartbeat counter=0\n';
      const after = 'header\n'
          'older log line\n'
          'Performing hot reload...       \n'
          'Reloaded 0 libraries in 45ms.\n';

      expect(after.length, equals(before.length));

      final result = didLogGainMarker(
        before: before,
        after: after,
        marker: 'Reloaded',
      );

      expect(result, isTrue);
    });
  });
}
