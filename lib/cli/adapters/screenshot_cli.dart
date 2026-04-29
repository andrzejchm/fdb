import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/constants.dart';
import 'package:fdb/core/commands/screenshot/screenshot.dart';

/// CLI adapter for `fdb screenshot`.
///
/// Parses `--output <path>` / `-o <path>` (defaults to [defaultScreenshotPath])
/// and `--full` flag, delegates to [captureScreenshot], then emits:
///
///   `SCREENSHOT_SAVED=<path>`        (stdout, success)
///   `SIZE=<n>B|<n.n>KB|<n.n>MB`     (stdout, success)
///   WARNING: …                       (stderr, zero or more, before tokens)
///   ERROR: …                         (stderr, failure)
Future<int> runScreenshotCli(List<String> args) =>
    runCliAdapter(_buildParser(), args, _execute);

ArgParser _buildParser() => ArgParser()
  ..addOption(
    'output',
    abbr: 'o',
    defaultsTo: defaultScreenshotPath,
    help: 'Output file path (default: <session-dir>/screenshot.png)',
  )
  ..addFlag(
    'full',
    negatable: false,
    help: 'Skip downscaling; keep native resolution',
  );

Future<int> _execute(ArgResults results) async {
  final input = (
    output: results['output'] as String,
    fullResolution: results['full'] as bool,
  );
  final result = await captureScreenshot(input);
  return _format(result);
}

int _format(ScreenshotResult result) {
  switch (result) {
    case ScreenshotSaved(:final path, :final sizeBytes, :final warnings):
      for (final w in warnings) {
        stderr.writeln(w);
      }
      stdout.writeln('SCREENSHOT_SAVED=$path');
      stdout.writeln('SIZE=${_formatSize(sizeBytes)}');
      return 0;
    case ScreenshotFailed(:final message, :final warnings):
      for (final w in warnings) {
        stderr.writeln(w);
      }
      stderr.writeln('ERROR: $message');
      return 1;
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
