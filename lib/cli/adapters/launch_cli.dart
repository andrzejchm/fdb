import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/cli/interactive_repl.dart';
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
///   --dart-define  Pass a --dart-define to flutter run (repeatable)
///   --dart-define-from-file
///                  Pass a --dart-define-from-file to flutter run (repeatable)
///   --verbose      Pass --verbose to flutter run
///   --interactive  Start an fdb REPL after launching
Future<int> runLaunchCli(List<String> args, {String? sessionDir}) => runCliAdapter(
      ArgParser()
        ..addOption('device', help: '(required) target device/simulator ID')
        ..addOption('project', help: 'Flutter project root (default: CWD)')
        ..addOption('flavor', help: 'Build flavor')
        ..addOption(
          'target',
          help: 'Entry-point file (default: lib/main.dart)',
        )
        ..addOption('flutter-sdk', help: 'Path to Flutter SDK root')
        ..addMultiOption(
          'dart-define',
          help: 'Pass a --dart-define=KEY=VALUE to flutter run (repeatable)',
        )
        ..addMultiOption(
          'dart-define-from-file',
          help: 'Pass a --dart-define-from-file to flutter run (repeatable)',
        )
        ..addFlag(
          'verbose',
          negatable: false,
          help: 'Pass --verbose to flutter run',
        )
        ..addFlag(
          'interactive',
          abbr: 'i',
          negatable: false,
          help: 'Start an fdb REPL after launching',
        ),
      args,
      (results) => _execute(results, sessionDir: sessionDir),
    );

Future<int> _execute(ArgResults results, {String? sessionDir}) async {
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
    sessionDir: sessionDir,
    verbose: results['verbose'] as bool,
    interactive: results['interactive'] as bool,
    dartDefines: results['dart-define'] as List<String>,
    dartDefineFromFiles: results['dart-define-from-file'] as List<String>,
  );

  final result = await launchApp(
    input,
    onProgress: (s) {
      if (s.startsWith('WARNING:')) {
        stderr.writeln(s);
      } else {
        stdout.writeln(s);
      }
    },
  );

  final exitCode = _format(result);
  if (exitCode == 0 && input.interactive) {
    return runInteractiveRepl();
  }
  return exitCode;
}

int _format(LaunchResult result) {
  switch (result) {
    case LaunchSuccess():
      for (final token in launchSuccessTokens(result)) {
        stdout.writeln(token);
      }
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

    case LaunchProcessDied(noLogFile: false, :final fullLog):
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

List<String> launchSuccessTokens(LaunchSuccess result) => [
      'APP_STARTED',
      'VM_SERVICE_URI=${result.vmServiceUri}',
      'PID=${result.pid}',
      'LOG_FILE=${result.logFilePath}',
    ];
