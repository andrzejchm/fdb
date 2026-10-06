import 'dart:io';

import 'package:fdb/cli/adapters/launch_cli.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/constants.dart';
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

    test('--timeout accepts positive seconds and defaults when absent', () {
      int? parse(List<String> extra) => readTimeoutSecondsOption(
            buildLaunchArgParser().parse(['--device', 'macos', ...extra]),
            defaultSeconds: launchTimeoutSeconds,
          );

      expect(parse([]), launchTimeoutSeconds);
      expect(parse(['--timeout', '900']), 900);
      for (final invalid in ['abc', '0', '-5', '1.5']) {
        expect(parse(['--timeout=$invalid']), isNull, reason: invalid);
      }
    });

    test('rejects an invalid --timeout with the standard error line', () async {
      final result = await Process.run('dart', ['bin/fdb.dart', 'launch', '--device', 'macos', '--timeout', 'abc']);

      expect(result.exitCode, 1);
      expect((result.stderr as String).trim(), 'ERROR: Invalid value for --timeout: abc');
    });

    test('advertises passthrough launch flags in help', () {
      final usage = buildLaunchArgParser().usage;

      expect(usage, contains('--dart-define'));
      expect(usage, contains('--dart-define-from-file'));
    });
  });
}
