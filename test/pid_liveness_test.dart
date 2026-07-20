import 'dart:io';

import 'package:fdb/src/controller/pid_liveness.dart';
import 'package:test/test.dart';

void main() {
  group('isProcessAlive (POSIX branch — exercised on the current host)', () {
    test('returns true for the current process', () {
      expect(isProcessAlive(pid), isTrue);
    });

    test('returns false for a PID that does not exist', () {
      // PIDs above 4194304 (Linux's traditional max) are never assigned.
      expect(isProcessAlive(999999999), isFalse);
    });
  });

  group('tasklistOutputHasPid (Windows CSV parsing — testable without a Windows host)', () {
    test('returns true when the CSV output contains a matching PID column', () {
      const output = '"flutter.exe","4821","Console","1","123,456 K"';

      expect(tasklistOutputHasPid(output, 4821), isTrue);
    });

    test('returns false when tasklist reports no matching tasks', () {
      const output = 'INFO: No tasks are running which match the specified criteria.';

      expect(tasklistOutputHasPid(output, 4821), isFalse);
    });

    test('returns false for empty output', () {
      expect(tasklistOutputHasPid('', 4821), isFalse);
    });

    test('returns false when a different PID is present', () {
      const output = '"flutter.exe","1234","Console","1","123,456 K"';

      expect(tasklistOutputHasPid(output, 4821), isFalse);
    });

    test('is tolerant of surrounding whitespace/newlines', () {
      const output = '\n\r\n"dart.exe","9001","Console","1","50,000 K"\r\n';

      expect(tasklistOutputHasPid(output, 9001), isTrue);
    });
  });
}
