import 'package:fdb/cli/adapters/attach_cli.dart';
import 'package:fdb/core/commands/attach/attach.dart';
import 'package:test/test.dart';

void main() {
  group('attach CLI output contract', () {
    test('success tokens stay machine-readable and ordered', () {
      final result = AttachSuccess(
        vmServiceUri: 'ws://127.0.0.1:12345/abc=/ws',
        pid: '4321',
        logFilePath: '/tmp/project/.fdb/logs.txt',
      );

      expect(
        attachSuccessTokens(result),
        [
          'APP_ATTACHED',
          'VM_SERVICE_URI=ws://127.0.0.1:12345/abc=/ws',
          'PID=4321',
          'LOG_FILE=/tmp/project/.fdb/logs.txt',
        ],
      );
    });
  });

  group('attach CLI parser', () {
    test('advertises attach discovery flags in help', () {
      final usage = buildAttachArgParser().usage;

      expect(usage, contains('--device'));
      expect(usage, contains('--app-id'));
      expect(usage, contains('--debug-url'));
      expect(usage, contains('--interactive'));
    });
  });
}
