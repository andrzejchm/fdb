import 'package:fdb/src/controller/process_utils.dart';
import 'package:test/test.dart';

void main() {
  group('isToolOnPath (which/where dispatch — which branch exercised on the current host)', () {
    test('returns true for a tool that is definitely on PATH', () {
      // The test runner itself is invoked via `dart`, so it must be resolvable.
      expect(isToolOnPath('dart'), isTrue);
    });

    test('returns false for a tool name that does not exist', () {
      expect(isToolOnPath('fdb-definitely-not-a-real-binary-xyz'), isFalse);
    });
  });
}
