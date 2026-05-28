import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/cli/interactive_repl.dart';
import 'package:fdb/core/commands/attach/attach.dart';

/// CLI adapter for `fdb attach`.
ArgParser buildAttachArgParser() => ArgParser()
  ..addOption('device', help: '(required) target device/simulator ID')
  ..addOption('project', help: 'Flutter project root (default: CWD)')
  ..addOption('flavor', help: 'Build flavor used for app id metadata')
  ..addOption(
    'target',
    help: 'Entry-point file used by flutter attach when needed',
  )
  ..addOption('flutter-sdk', help: 'Path to Flutter SDK root')
  ..addOption(
    'app-id',
    help: 'Android package name or iOS/macOS bundle id for attach discovery',
  )
  ..addOption(
    'debug-url',
    help: 'Dart VM service URL copied from Xcode, logs, or DevTools output',
  )
  ..addFlag(
    'verbose',
    negatable: false,
    help: 'Pass --verbose to flutter attach',
  )
  ..addFlag(
    'interactive',
    abbr: 'i',
    negatable: false,
    help: 'Start an fdb REPL after attaching',
  );

Future<int> runAttachCli(List<String> args, {String? sessionDir}) => runCliAdapter(
      buildAttachArgParser(),
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
    appId: results['app-id'] as String?,
    debugUrl: results['debug-url'] as String?,
    verbose: results['verbose'] as bool,
    interactive: results['interactive'] as bool,
  );

  final result = await attachApp(
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

int _format(AttachResult result) {
  switch (result) {
    case AttachSuccess():
      for (final token in attachSuccessTokens(result)) {
        stdout.writeln(token);
      }
      return 0;

    case AttachMissingDevice():
      stderr.writeln('ERROR: --device is required');
      return 1;

    case AttachControllerFailed(:final details):
      stderr.writeln('ERROR: Failed to start controller: $details');
      return 1;

    case AttachProcessDied(noLogFile: true):
      stderr.writeln(
        'ERROR: flutter attach exited and no log file was created',
      );
      return 1;

    case AttachProcessDied(noLogFile: false, :final fullLog):
      stderr.writeln('ERROR: flutter attach exited unexpectedly');
      stderr.writeln(
          'HINT: Launch a debug/profile Flutter app first, pass --app-id to disambiguate, or pass --debug-url from Xcode/logs.');
      if (fullLog.trim().isNotEmpty) {
        stderr.writeln('--- log context ---');
        final lines = fullLog.trimRight().split('\n');
        for (final line in lines.length > 10 ? lines.sublist(lines.length - 10) : lines) {
          stderr.writeln(line);
        }
        stderr.writeln('---');
      }
      return 1;

    case AttachTimeout(:final tailLogLines):
      stdout.writeln('ATTACH_TIMEOUT');
      stdout.writeln(
          'HINT: Launch a debug/profile Flutter app first, pass --app-id to disambiguate, or pass --debug-url from Xcode/logs.');
      for (final line in tailLogLines) {
        stdout.writeln(line);
      }
      return 1;

    case AttachError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

List<String> attachSuccessTokens(AttachSuccess result) => [
      'APP_ATTACHED',
      'VM_SERVICE_URI=${result.vmServiceUri}',
      'PID=${result.pid}',
      'LOG_FILE=${result.logFilePath}',
    ];
