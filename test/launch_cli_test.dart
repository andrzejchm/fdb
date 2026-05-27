import 'package:fdb/cli/adapters/launch_cli.dart';
import 'package:fdb/core/commands/launch/launch.dart';
import 'package:test/test.dart';

void main() {
  group('launch CLI output contract', () {
    test('success tokens stay machine-readable and ordered', () {
      final result = LaunchSuccess(
        vmServiceUri: 'ws://127.0.0.1:12345/abc=/ws',
        pid: '4321',
        logFilePath: '/tmp/project/.fdb/logs.txt',
      );

      expect(
        launchSuccessTokens(result),
        [
          'APP_STARTED',
          'VM_SERVICE_URI=ws://127.0.0.1:12345/abc=/ws',
          'PID=4321',
          'LOG_FILE=/tmp/project/.fdb/logs.txt',
        ],
      );
    });
  });

  group('launch CLI parser', () {
    test('keeps commas inside dart-define values', () {
      final results = buildLaunchArgParser().parse([
        '--device',
        'macos',
        '--dart-define',
        'API_BASE_URL=https://example.com/v1,canary',
      ]);

      expect(
        results['dart-define'],
        ['API_BASE_URL=https://example.com/v1,canary'],
      );
    });

    test('advertises passthrough launch flags in help', () {
      final usage = buildLaunchArgParser().usage;

      expect(usage, contains('--dart-define'));
      expect(usage, contains('--dart-define-from-file'));
    });
  });
}
