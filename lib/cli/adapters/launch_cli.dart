import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/launch/launch.dart';
import 'package:fdb/core/launch_failure_analyzer.dart';

/// CLI adapter for `fdb launch`.
///
/// Flags:
///   --device       (required) target device/simulator ID
///   --project      Flutter project root (default: CWD)
///   --flavor       Build flavor
///   --target       Entry-point file (default: lib/main.dart)
///   --flutter-sdk  Path to Flutter SDK root
///   --verbose      Pass --verbose to flutter run
Future<int> runLaunchCli(List<String> args) => runCliAdapter(
      ArgParser()
        ..addOption('device', help: '(required) target device/simulator ID')
        ..addOption('project', help: 'Flutter project root (default: CWD)')
        ..addOption('flavor', help: 'Build flavor')
        ..addOption(
          'target',
          help: 'Entry-point file (default: lib/main.dart)',
        )
        ..addOption('flutter-sdk', help: 'Path to Flutter SDK root')
        ..addFlag('verbose', negatable: false, help: 'Pass --verbose to flutter run'),
      args,
      _execute,
    );

Future<int> _execute(ArgResults results) async {
  final device = results['device'] as String?;

  if (device == null) {
    stderr.writeln('ERROR: --device is required');
    return 1;
  }

  final input = (
    device: device,
    project: results['project'] as String?,
    flavor: results['flavor'] as String?,
    target: results['target'] as String?,
    flutterSdk: results['flutter-sdk'] as String?,
    verbose: results['verbose'] as bool,
  );

  final result = await launchApp(
    input,
    onProgress: (s) {
      // Warnings go to stderr; all other progress tokens (e.g. WAITING...) go
      // to stdout so callers can distinguish them.
      if (s.startsWith('WARNING:')) {
        stderr.writeln(s);
      } else {
        stdout.writeln(s);
      }
    },
  );

  return _format(result);
}

int _format(LaunchResult result) {
  switch (result) {
    case LaunchSuccess(:final vmServiceUri, :final pid, :final logFilePath):
      stdout.writeln('APP_STARTED');
      stdout.writeln('VM_SERVICE_URI=$vmServiceUri');
      stdout.writeln('PID=$pid');
      stdout.writeln('LOG_FILE=$logFilePath');
      return 0;

    case LaunchMissingDevice():
      stderr.writeln('ERROR: --device is required');
      return 1;

    case LaunchLauncherFailed(:final details):
      stderr.writeln('ERROR: Failed to start launcher: $details');
      return 1;

    case LaunchInvalidLauncherPid():
      stderr.writeln('ERROR: Could not read launcher PID');
      return 1;

    case LaunchProcessDied(noLogFile: true):
      stderr.writeln(
        'ERROR: flutter process exited and no log file was created',
      );
      return 1;

    case LaunchProcessDied(:final fullLog) when fullLog.isNotEmpty:
      final analysis = analyzeLaunchFailure(fullLog);
      stderr.writeln('ERROR: flutter process exited unexpectedly');
      stderr.writeln('LAUNCH_ERROR=${analysis.category}');
      stderr.writeln('LAUNCH_ERROR_CAUSE=${analysis.rootCause}');
      if (analysis.remediationHint != null) {
        stderr.writeln('HINT: ${analysis.remediationHint}');
      }
      if (analysis.contextLines.isNotEmpty) {
        stderr.writeln('--- log context ---');
        for (final line in analysis.contextLines) {
          stderr.writeln(line);
        }
        stderr.writeln('---');
      }
      return 1;

    case LaunchProcessDied(:final tailLogLines):
      stderr.writeln('ERROR: flutter process exited unexpectedly');
      for (final line in tailLogLines) {
        stderr.writeln(line);
      }
      return 1;

    case LaunchTimeout(:final tailLogLines):
      stdout.writeln('LAUNCH_TIMEOUT');
      for (final line in tailLogLines) {
        stdout.writeln(line);
      }
      return 1;

    case LaunchError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
